module Cogni
  module Workflows
    module Declarative
    class RunExecutor
      def run(ref : String, ctx : NodeContext, runtime : AnyHash? = nil, env : AnyHash? = nil, workflow_root : String? = nil) : AnyHash
        if runtime
          run_external(ref, ctx, runtime, env, workflow_root)
        else
          Cogni::RegistryApi.call_function(ref, ctx)
        end
      end

      private def run_external(ref : String, ctx : NodeContext, runtime : AnyHash, env : AnyHash?, workflow_root : String?) : AnyHash
        script_path = resolve_script_ref(ref, workflow_root)
        command, args = command_for_runtime(runtime, script_path)

        stdout = IO::Memory.new
        stderr = IO::Memory.new
        input = IO::Memory.new(ctx.state.to_json)
        exec_env = build_exec_env(env)

        status = Process.run(command, args: args, input: input, output: stdout, error: stderr, env: exec_env)
        unless status.success?
          raise "run external failed: #{ref} exited #{status.exit_code}: #{stderr.to_s.strip}"
        end

        output = stdout.to_s.strip
        raise "run external produced empty stdout: #{ref}" if output.empty?

        parsed = JSON.parse(output).as_h?
        raise "run external must output a JSON object: #{ref}" unless parsed
        parsed
      rescue ex : JSON::ParseException
        raise "run external produced invalid JSON: #{ref}: #{ex.message}"
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
        path = File.join("/tmp", "cogni-inline-#{Random::Secure.hex(8)}#{ext}")
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
end
