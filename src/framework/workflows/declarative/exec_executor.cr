require "digest/sha256"
require "http/client"
require "uri"
require "../../mcp/manager"
require "../../discovery/cawfile_loader"
require "../../discovery/git_https_puller"
require "../../telemetry"
require "./acp_executor"

module Ocawe
  module Workflow
    class ExecExecutor
      def exec(ref : String, ctx : NodeContext, runtime : AnyHash? = nil, env : AnyHash? = nil, workflow_root : String? = nil) : AnyHash
        started = Time.monotonic
        status = "success"
        span = Ocawe::Telemetry.start_span(
          "workflow.exec",
          {
            "workflow.id"      => ctx.workflow_id,
            "workflow.run_id"  => ctx.run_id,
            "workflow.node_id" => ctx.node_id,
            "exec.ref"         => ref,
          } of String => Ocawe::Telemetry::AttributeValue
        )
        begin
          if runtime.nil? && ref.starts_with?("mcp:")
            return exec_mcp_tool(ref, ctx)
          end

          raise "exec requires runtime for non-mcp refs: #{ref}" unless runtime

          # Check for ACP runtime
          if acp_config = runtime["acp"]?
            return exec_acp(ref, ctx, acp_config, env, workflow_root)
          end

          if runtime.has_key?("git+https")
            return exec_git(ref, ctx, "git+https")
          end

          if runtime.has_key?("git+ssh")
            return exec_git(ref, ctx, "git+ssh")
          end

          exec_external(ref, ctx, runtime, env, workflow_root)
        rescue ex
          status = "error"
          raise ex
        ensure
          duration_ms = (Time.monotonic - started).total_milliseconds
          attrs = {
            "exec.ref"                  => ref,
            "workflow.status"           => status,
            "workflow.exec.duration_ms" => duration_ms,
          } of String => Ocawe::Telemetry::AttributeValue
          Ocawe::Telemetry.finish_span(span, status: status, error: status == "error" ? "exec failed" : nil, attributes: attrs)
        end
      end

      private def exec_acp(ref : String, ctx : NodeContext, acp_config : JSON::Any, env : AnyHash?, workflow_root : String?) : AnyHash
        config = acp_config.as_h? || {} of String => JSON::Any
        input = acp_prompt_input(ctx.input_data)

        # Build environment
        exec_env = build_exec_env(env) || {} of String => String

        # Resolve working directory
        cwd = workflow_root || Dir.current

        executor = ACPExecutor.new(ref, cwd, exec_env)
        executor.run(ref, input, config)
      end

      private def acp_prompt_input(input_data : AnyHash) : String
        input_data["prompt"]?.try(&.as_s?) || input_data.to_json
      end

      private def exec_mcp_tool(ref : String, ctx : NodeContext) : AnyHash
        server_id, tool_name = Ocawe::MCP.parse_mcp_ref(ref)
        arguments = ctx.input_data["input"]?.try(&.as_h?) || ctx.input_data
        Ocawe::MCP.manager.call_tool(server_id, tool_name, arguments)
      end

      private def exec_git(ref : String, ctx : NodeContext, transport : String) : AnyHash
        pulled = ACD::Discovery::GitHttpsPuller.new.pull(ref, transport)
        workflow_id, cawfile = resolve_remote_caw_workflow(pulled)
        binary = compile_remote_caw_binary(pulled, cawfile)
        run = run_remote_caw_binary(binary, pulled.local_path, workflow_id, ctx)

        cawfile_path = if Dir.exists?(pulled.local_path)
                         ACD::Discovery::CawfileLoader.find_cawfile(pulled.local_path)
                       end

        {
          "transport"   => JSON.parse(pulled.transport.to_json),
          "ref"         => JSON.parse(pulled.ref.to_json),
          "repo"        => JSON.parse(pulled.repo_slug.to_json),
          "repo_url"    => JSON.parse(pulled.repo_url.to_json),
          "repo_dir"    => JSON.parse(pulled.repo_dir.to_json),
          "local_path"  => JSON.parse(pulled.local_path.to_json),
          "workflow_id" => JSON.parse(workflow_id.to_json),
          "cawfile"     => JSON.parse(cawfile_path.to_json),
          "binary"      => JSON.parse(binary.to_json),
          "run"         => JSON.parse(run.to_json),
          "cloned"      => JSON.parse(pulled.cloned.to_json),
          "pulled"      => JSON.parse(pulled.pulled.to_json),
        } of String => JSON::Any
      end

      private def resolve_remote_caw_workflow(pulled : ACD::Discovery::GitHttpsPullResult)
        if workflow_id = pulled.workflow_id
          cawfile = ACD::Discovery::CawfileLoader.load(pulled.local_path, workflow_id)
          raise "#{pulled.local_path}: unknown remote workflow '#{workflow_id}'" unless cawfile
          return {workflow_id, cawfile}
        end

        cawfiles = ACD::Discovery::CawfileLoader.load_all(pulled.local_path)
        raise "#{pulled.local_path}: remote Cawfile has no workflow blocks" if cawfiles.empty?
        if cawfiles.size > 1
          ids = cawfiles.map(&.id).join(", ")
          raise "#{pulled.local_path}: remote Cawfile has multiple workflows (#{ids}); append /<workflow-id> to the ref"
        end

        cawfile = cawfiles.first
        {cawfile.id, cawfile}
      end

      private def compile_remote_caw_binary(pulled : ACD::Discovery::GitHttpsPullResult, cawfile : ACD::Discovery::CawfileBundle) : String
        source_root = ocawe_source_root
        runtime_entry = File.join(source_root, "src", "ocawe.cr")
        unless File.file?(runtime_entry)
          raise "remote Cawfile exec requires Ocawe source at #{source_root}"
        end
        unless command_available?("crystal")
          raise "remote Cawfile exec requires crystal compiler in PATH"
        end

        digest = Digest::SHA256.hexdigest("#{pulled.transport}:#{pulled.ref}:#{File.info(ACD::Discovery::CawfileLoader.find_cawfile(pulled.local_path) || pulled.local_path).modification_time.to_unix_ms}")[0, 16]
        build_dir = File.join(pulled.repo_dir, ".ocawe", "binaries", digest)
        binary = File.join(build_dir, "ocawecore")
        return binary if File.file?(binary) && !pulled.pulled

        entrypoint = File.join(build_dir, "entrypoint.cr")
        Dir.mkdir_p(build_dir)
        entrypoint_dir = File.dirname(entrypoint)
        crystal_loader = cawfile.crystal_loader
        cawfile_code = crystal_loader.try(&.code) || [] of String
        registry_files = crystal_loader.try(&.registry_files) || [] of String

        File.write(entrypoint, String.build do |io|
          io << "require " << require_path(entrypoint_dir, runtime_entry).to_json << "\n"
          cawfile_code.each { |line| io << line << "\n" }
          registry_files.each do |registry_file|
            io << "require " << require_path(entrypoint_dir, registry_file).to_json << "\n"
          end
          io << "\nOcaweCore.run\n"
        end)

        status = Process.run(
          "crystal",
          args: ["build", entrypoint, "--release", "--no-debug", "-Docawe_runtime_main", "-o", binary],
          chdir: source_root,
          input: Process::Redirect::Close,
          output: Process::Redirect::Inherit,
          error: Process::Redirect::Inherit
        )
        raise "remote Cawfile compile failed: #{pulled.ref}" unless status.success?
        binary
      end

      private def run_remote_caw_binary(binary : String, workflows_root : String, workflow_id : String, ctx : NodeContext) : AnyHash
        port = 20000 + Random.rand(20000)
        process = Process.new(
          binary,
          args: ["--port=#{port}"],
          chdir: workflows_root,
          input: Process::Redirect::Close,
          output: Process::Redirect::Inherit,
          error: Process::Redirect::Inherit
        )
        begin
          wait_for_remote_runtime!(port)
          input_data = ctx.state.empty? ? ctx.input_data : ctx.state
          payload = {"input_data" => JSON.parse(input_data.to_json)} of String => JSON::Any
          headers = HTTP::Headers{"Content-Type" => "application/json"}
          if traceparent = Ocawe::Telemetry.traceparent
            headers["traceparent"] = traceparent
          end
          path = "/v1/workflows/#{URI.encode_path_segment(workflow_id)}/runs"
          response = HTTP::Client.post("http://127.0.0.1:#{port}#{path}", headers: headers, body: payload.to_json)
          unless response.status_code >= 200 && response.status_code < 300
            raise "remote workflow #{workflow_id} failed HTTP #{response.status_code}: #{response.body}"
          end
          parsed = JSON.parse(response.body).as_h?
          raise "remote workflow #{workflow_id} returned non-object response" unless parsed
          parsed
        ensure
          terminate_process(process)
        end
      end

      private def terminate_process(process : Process) : Nil
        process.terminate
        process.wait
      rescue
      end

      private def wait_for_remote_runtime!(port : Int32) : Nil
        deadline = Time.monotonic + 15.seconds
        loop do
          begin
            response = HTTP::Client.get("http://127.0.0.1:#{port}/health")
            return if response.status_code == 200
          rescue
          end
          raise "remote Cawfile runtime did not become healthy on port #{port}" if Time.monotonic > deadline
          sleep 100.milliseconds
        end
      end

      private def ocawe_source_root : String
        if executable = Process.executable_path
          source = File.expand_path("../share/ocawe/source", File.dirname(executable))
          return source if File.file?(File.join(source, "src", "ocawe.cr"))
        end

        File.expand_path("../../../..", __DIR__)
      end

      private def require_path(from_dir : String, target : String) : String
        relative = Path[File.expand_path(target)].relative_to(Path[File.expand_path(from_dir)]).to_s
        relative = "./#{relative}" unless relative.starts_with?(".")
        relative.sub(/\.cr$/, "")
      end

      private def command_available?(name : String) : Bool
        Process.run("sh", args: ["-c", "command -v #{name} >/dev/null 2>&1"], output: Process::Redirect::Close, error: Process::Redirect::Close).success?
      end

      private def exec_external(ref : String, ctx : NodeContext, runtime : AnyHash, env : AnyHash?, workflow_root : String?) : AnyHash
        script_path = resolve_script_ref(ref, workflow_root)
        command, args = command_for_runtime(runtime, script_path)

        stdout = IO::Memory.new
        stderr = IO::Memory.new
        input = IO::Memory.new(ctx.state.to_json)
        exec_env = build_exec_env(env)

        status = Process.run(command, args: args, input: input, output: stdout, error: stderr, env: exec_env)
        unless status.success?
          raise "exec external failed: #{ref} exited #{status.exit_code}: #{stderr.to_s.strip}"
        end

        output = stdout.to_s.strip
        raise "exec external produced empty stdout: #{ref}" if output.empty?

        parsed = JSON.parse(output).as_h?
        raise "exec external must output a JSON object: #{ref}" unless parsed
        parsed
      rescue ex : JSON::ParseException
        raise "exec external produced invalid JSON: #{ref}: #{ex.message}"
      end

      private def build_exec_env(env : AnyHash?) : Hash(String, String)?
        return nil unless env

        prepared = {} of String => String
        env.each do |k, v|
          prepared[k] = v.as_s? || v.raw.to_s
        end
        prepared
      end

      private def command_for_runtime(runtime : AnyHash, script_path : String) : {String, Array(String)}
        if explicit = runtime["exec"]?.try(&.as_s?)
          args = runtime["args"]?.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String
          return {explicit, args + [script_path]}
        end

        key = runtime.keys.first?
        raise "runtime object must contain at least one key" unless key

        case key
        when "node"
          {"node", [script_path]}
        when "python"
          {"python3", [script_path]}
        when "shell"
          shell = runtime["shell"]?.try(&.as_s?) || "bash"
          {shell, [script_path]}
        else
          {key, [script_path]}
        end
      end

      private def resolve_script_ref(ref : String, workflow_root : String?) : String
        if file_path = resolve_existing_script_path(ref, workflow_root)
          return file_path
        end

        write_inline_script(ref)
      end

      private def resolve_existing_script_path(ref : String, workflow_root : String?) : String?
        if ref.starts_with?("/")
          return File.file?(ref) ? ref : nil
        end

        root = workflow_root || Dir.current
        expanded_root = File.expand_path(root)
        resolved = File.expand_path(ref, expanded_root)
        if (resolved.starts_with?(expanded_root + "/") || resolved == expanded_root) && File.file?(resolved)
          return resolved
        end

        global_root = File.expand_path("./tools")
        global_resolved = File.expand_path(ref, global_root)
        if (global_resolved.starts_with?(global_root + "/") || global_resolved == global_root) && File.file?(global_resolved)
          return global_resolved
        end

        nil
      end

      private def write_inline_script(script : String) : String
        ext = inline_script_extension(script)
        path = File.join("/tmp", "ocawe-inline-#{Random::Secure.hex(8)}#{ext}")
        File.write(path, script)
        path
      end

      private def inline_script_extension(script : String) : String
        if script.includes?("module.exports") || script.includes?("require(") || script.includes?("process.")
          ".js"
        elsif script.includes?("import ") || script.includes?("export ")
          ".mjs"
        elsif script.includes?("def ") || script.includes?("print(")
          ".py"
        else
          ".sh"
        end
      end
    end
  end
end
