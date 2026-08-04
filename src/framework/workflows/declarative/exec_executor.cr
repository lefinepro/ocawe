require "digest/sha256"
require "http/client"
require "uri"
require "../../mcp/manager"
require "../../discovery/cawfile_loader"
require "../../discovery/git_https_puller"
require "../../telemetry"
require "../../utils/time_compat"
require "./acp_executor"

module Ocawe
  module Workflow
    class ExecExecutor
      def exec(ref : String, ctx : NodeContext, runtime : AnyHash? = nil, env : AnyHash? = nil, workflow_root : String? = nil) : AnyHash
        started = Ocawe::Utils::TimeCompat.monotonic
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
            return exec_acp(ref, ctx, acp_config, runtime, env, workflow_root)
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
          duration_ms = Ocawe::Utils::TimeCompat.elapsed_milliseconds(started)
          attrs = {
            "exec.ref"                  => ref,
            "workflow.status"           => status,
            "workflow.exec.duration_ms" => duration_ms,
          } of String => Ocawe::Telemetry::AttributeValue
          Ocawe::Telemetry.finish_span(span, status: status, error: status == "error" ? "exec failed" : nil, attributes: attrs)
        end
      end

      private def exec_acp(ref : String, ctx : NodeContext, acp_config : JSON::Any, runtime : AnyHash, env : AnyHash?, workflow_root : String?) : AnyHash
        config = acp_config.as_h? || {} of String => JSON::Any
        config = config.dup
        if placement = runtime["placement"]?
          config["placement"] = merge_workspace_placement(placement, ctx)
        end
        input = acp_prompt_input(ctx.input_data)

        # Build environment
        exec_env = build_exec_env(env) || {} of String => String

        # Resolve working directory
        cwd = resolve_acp_cwd(config, ctx, workflow_root)
        fs_policy = build_filesystem_policy(ctx, cwd)

        executor = ACPExecutor.new(ref, cwd, exec_env, fs_policy)
        executor.run(ref, input, config)
      end

      private def acp_prompt_input(input_data : AnyHash) : String
        if prompt = input_data["prompt"]?.try(&.as_s?)
          prompt
        else
          input_data.to_json
        end
      end

      private def resolve_acp_cwd(config : Hash(String, JSON::Any), ctx : NodeContext, workflow_root : String?) : String
        if cwd = config["cwd"]?.try(&.as_s?)
          return File.expand_path(cwd)
        end
        if env_workspace_path = ENV["OCAWE_AGENT_WORKSPACE_PATH"]?
          return File.expand_path(env_workspace_path) unless env_workspace_path.empty?
        end
        if workspace = ctx.input_data["workspace"]?.try(&.as_h?)
          if workspace_path = workspace["path"]?.try(&.as_s?)
            return File.expand_path(workspace_path)
          end
        end
        File.expand_path(workflow_root || Dir.current)
      end

      private def build_filesystem_policy(ctx : NodeContext, cwd : String) : ACP::Client::FilesystemPolicy
        workspace = ctx.input_data["workspace"]?.try(&.as_h?)
        root = ENV["OCAWE_AGENT_WORKSPACE_PATH"]? || workspace.try { |value| value["path"]?.try(&.as_s?) } || cwd
        write_policy = ENV["OCAWE_AGENT_WRITE_POLICY"]? || workspace.try { |value| value["write_policy"]?.try(&.as_s?) || value["writePolicy"]?.try(&.as_s?) } || "write"
        ACP::Client::FilesystemPolicy.new(root, write_policy)
      end

      private def merge_workspace_placement(placement : JSON::Any, ctx : NodeContext) : JSON::Any
        merged = placement.as_h?.try(&.dup) || {} of String => JSON::Any
        workspace = ctx.input_data["workspace"]?.try(&.as_h?)
        if env_path = ENV["OCAWE_AGENT_WORKSPACE_PATH"]?
          merged["path"] = JSON.parse(env_path.to_json) unless env_path.empty?
        elsif workspace
          if path = workspace.not_nil!["path"]?
            merged["path"] ||= path
          end
        end
        if env_host_path = ENV["OCAWE_AGENT_HOST_PATH"]?
          merged["host_path"] = JSON.parse(env_host_path.to_json) unless env_host_path.empty?
        elsif workspace
          if host_path = workspace.not_nil!["host_path"]? || workspace.not_nil!["hostPath"]?
            merged["host_path"] ||= host_path
          end
        end
        JSON.parse(merged.to_json)
      end

      private def exec_mcp_tool(ref : String, ctx : NodeContext) : AnyHash
        server_id, tool_name = Ocawe::MCP.parse_mcp_ref(ref)
        arguments = ctx.input_data["input"]?.try(&.as_h?) || ctx.input_data
        Ocawe::MCP.manager.call_tool(server_id, tool_name, arguments)
      end

      private def exec_git(ref : String, ctx : NodeContext, transport : String) : AnyHash
        pulled = ACD::Discovery::GitHttpsPuller.new.pull(ref, transport)
        workflow_id, cawfile = resolve_remote_caw_workflow(pulled)
        binary = direct_remote_caw_runtime_binary(pulled, cawfile)
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

      private def direct_remote_caw_runtime_binary(pulled : ACD::Discovery::GitHttpsPullResult, cawfile : ACD::Discovery::CawfileBundle) : String
        _ = pulled
        _ = cawfile
        binary = Process.executable_path
        binary || ""
      end

      private def executable_file?(path : String) : Bool
        info = File.info(path)
        File.file?(path) && (info.permissions.value & 0o111) != 0
      rescue
        false
      end

      private def shell_escape(value : String) : String
        "'" + value.gsub("'", "'\"'\"'") + "'"
      end

      private def run_remote_caw_binary(binary : String, workflows_root : String, workflow_id : String, ctx : NodeContext) : AnyHash
        port = 20000 + Random.rand(20000)
        command, args = remote_runtime_command(binary, workflows_root, port)
        process = Process.new(
          command,
          args: args,
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

      private def remote_runtime_command(binary : String, workflows_root : String, port : Int32) : {String, Array(String)}
        if !binary.empty? && executable_file?(binary) && File.basename(binary).includes?("ocawecore")
          return {binary, ["--port=#{port}"]}
        end

        if override = ENV["OCAWECORE_BINARY"]?
          return {override, ["--port=#{port}"]} if executable_file?(override)
        end

        unless command_available?("crystal")
          raise "remote Cawfile exec requires ocawecore or crystal in PATH"
        end

        source_root = ocawe_source_root
        runtime_entry = File.join(source_root, "src", "ocawe.cr")
        raise "remote Cawfile exec requires Ocawe source at #{source_root}" unless File.file?(runtime_entry)
        command = "cd #{shell_escape(source_root)} && OCAWE_WORKFLOWS_ROOT=#{shell_escape(workflows_root)} crystal run #{shell_escape(runtime_entry)} -Docawe_runtime_main -- --port=#{port}"
        {"sh", ["-c", command]}
      end

      private def terminate_process(process : Process) : Nil
        process.terminate
        process.wait
      rescue
      end

      private def wait_for_remote_runtime!(port : Int32) : Nil
        deadline = Ocawe::Utils::TimeCompat.monotonic + 60.seconds
        loop do
          begin
            response = HTTP::Client.get("http://127.0.0.1:#{port}/health")
            return if response.status_code == 200
          rescue
          end
          raise "remote Cawfile runtime did not become healthy on port #{port}" if Ocawe::Utils::TimeCompat.monotonic > deadline
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
