module CogniCore
  module Workflow
    class ToolExecutor
      def run(tool_ref : String, ctx : NodeContext, runtime : AnyHash? = nil, workflow_root : String? = nil) : AnyHash
        if runtime
          run_external_tool(tool_ref, ctx, runtime, workflow_root)
        else
          run_crystal_tool(tool_ref, ctx)
        end
      end

      private def run_crystal_tool(function_name : String, ctx : NodeContext) : AnyHash
        Workflow.tool_registry.call(function_name, ctx, function_name: function_name)
      end

      private def run_external_tool(tool_path : String, ctx : NodeContext, runtime : AnyHash, workflow_root : String?) : AnyHash
        resolved_path = resolve_tool_path(tool_path, workflow_root)
        command, args = command_for_runtime(runtime, resolved_path)

        stdout = IO::Memory.new
        stderr = IO::Memory.new
        input = IO::Memory.new(ctx.state.to_json)

        status = Process.run(command, args: args, input: input, output: stdout, error: stderr)
        unless status.success?
          raise "external tool failed: #{tool_path} exited #{status.exit_code}: #{stderr.to_s.strip}"
        end

        output = stdout.to_s.strip
        raise "external tool produced empty stdout: #{tool_path}" if output.empty?

        parsed = JSON.parse(output).as_h?
        raise "external tool must output a JSON object: #{tool_path}" unless parsed
        parsed
      rescue ex : JSON::ParseException
        raise "external tool produced invalid JSON: #{tool_path}: #{ex.message}"
      end

      private def command_for_runtime(runtime : AnyHash, resolved_path : String) : {String, Array(String)}
        if explicit = runtime["exec"]?.try(&.as_s?)
          args = runtime["args"]?.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String
          return {explicit, args + [resolved_path]}
        end

        key = runtime.keys.first?
        raise "runtime object must contain at least one key" unless key

        case key
        when "node"
          {"node", [resolved_path]}
        when "python"
          {"python3", [resolved_path]}
        when "shell"
          shell = runtime["shell"]?.try(&.as_s?) || "bash"
          {shell, [resolved_path]}
        else
          {key, [resolved_path]}
        end
      end

      private def resolve_tool_path(tool_path : String, workflow_root : String?) : String
        if tool_path.starts_with?("/")
          raise "tool path not found: #{tool_path}" unless File.file?(tool_path)
          return tool_path
        end

        root = workflow_root || Dir.current
        expanded_root = File.expand_path(root)
        resolved = File.expand_path(tool_path, expanded_root)

        if (resolved.starts_with?(expanded_root + "/") || resolved == expanded_root) && File.file?(resolved)
          return resolved
        end

        # fallback to global tools root to support shared tools/ across workflows
        global_root = File.expand_path("./tools")
        global_resolved = File.expand_path(tool_path, global_root)

        unless global_resolved.starts_with?(global_root + "/") || global_resolved == global_root
          raise "tool path escapes workflow/global roots: #{tool_path}"
        end
        raise "tool path not found: #{resolved} (and global fallback #{global_resolved})" unless File.file?(global_resolved)

        global_resolved
      end
    end
  end
end
