require "json"
require "../../acp"

module Ocawe
  module Workflow
    # ACP executor - runs an external binary via the Agent Client Protocol
    #
    # Usage in Cawfile:
    #   exec "codex", runtime: { "acp" => { "command" => "codex", "args" => ["--server"] } }
    #   exec "claude", runtime: { "acp" => { "command" => "claude", "args" => ["--server"] } }
    #
    # Or using the shorthand:
    #   exec "codex", runtime: { "acp" => { "command" => "codex" } }
    class ACPExecutor
      def initialize(@node_id : String, @cwd : String = Dir.current, @env : Hash(String, String) = {} of String => String)
      end

      def run(ref : String, input : String, config : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
        command = resolve_command(ref, config)
        command_args = config["args"]?.try(&.as_a?(&.as_s?)) || [] of String
        cwd = config["cwd"]?.try(&.as_s?) || @cwd
        agent_env = merge_env(config["env"]?)

        # Initialize agent
        client = ACP::Client.new(command, command_args, agent_env)
        client.start

        # Create session
        session_id = client.create_session(cwd)

        begin
          # Send prompt
          result = client.prompt(input)

          # Collect updates (non-blocking, just collect what's available)
          updates = [] of ACP::SessionUpdate
          10.times do
            update = client.next_update(timeout: 2.seconds)
            break unless update
            updates << update
          end

          # Build output
          output = build_output(session_id, result, updates, config)
          output
        rescue ex : Exception
          raise "ACP node '#{ref}' failed: #{ex.message}"
        ensure
          client.close
        end
      end

      private def resolve_command(ref : String, config : Hash(String, JSON::Any)) : String
        if explicit_cmd = config["command"]?.try(&.as_s?)
          return explicit_cmd
        end

        # Use ref as the command name
        ref
      end

      private def merge_env(raw : JSON::Any?) : Hash(String, String)
        env = {} of String => String
        raw.try(&.as_h?).try do |h|
          h.each do |k, v|
            env[k.to_s] = v.as_s? || v.raw.to_s
          end
        end
        env
      end

      private def build_output(session_id : String, result : ACP::SessionPromptResult, updates : Array(ACP::SessionUpdate), config : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
        output = {} of String => JSON::Any

        # Extract content from updates
        content_parts = [] of String
        updates.each do |update|
          next unless update.update.content
          content_parts << update.update.content.text || ""
        end

        output["session_id"] = JSON.parse(session_id.to_json)
        output["stop_reason"] = JSON.parse(result.stop_reason.to_json)
        output["content"] = JSON.parse(content_parts.join(" ").to_json)
        output["message"] = content_parts.join(" ")

        # Include metadata from config
        output["metadata"] = config["metadata"]?.try(&.as_h?) || {} of String => JSON::Any

        output
      end
    end
  end
end
