require "json"
require "../../acp"

module Ocawe
  module Workflow
    # ACP executor - runs an external binary via the Agent Client Protocol
    #
    # Usage in Cawfile:
    #   exec "agent", runtime: { "acp" => { "command" => "agent" },
    #     "placement" => { "mode" => "container", "image" => "agent:latest" } }
    #
    # Or using the shorthand:
    #   exec "agent", runtime: { "acp" => { "command" => "agent" } }
    class ACPExecutor
      def initialize(
        @node_id : String,
        @run_id : String = "run",
        @cwd : String = Dir.current,
        @env : Hash(String, String) = {} of String => String,
      )
      end

      def run(ref : String, input : String, config : Hash(String, JSON::Any), placement : Hash(String, JSON::Any)? = nil, workspace : Hash(String, JSON::Any)? = nil) : Hash(String, JSON::Any)
        STDERR.flush
        command = resolve_command(ref, config)
        command_args = config["args"]?.try(&.as_a?).try(&.compact_map { |v| v.as_s? }) || [] of String
        cwd = config["cwd"]?.try(&.as_s?) || @cwd
        agent_env = merge_env(config["env"]?)

        if placement && placement["mode"]?.try(&.as_s?) == "container"
          STDERR.flush
          command, command_args, cwd, agent_env = container_command(command, command_args, cwd, agent_env, placement, workspace)
        end

        # Initialize agent
        STDERR.flush
        client = ACP::Client.new(command, command_args, agent_env)
        client.start
        STDERR.flush

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

      private def container_command(command : String, command_args : Array(String), cwd : String, agent_env : Hash(String, String), placement : Hash(String, JSON::Any), workspace : Hash(String, JSON::Any)?) : {String, Array(String), String, Hash(String, String)}
        tool = placement["tool"]?.try(&.as_s?) || ENV["OCAWE_CONTAINER_TOOL"]? || "nerdctl"
        image = placement["image"]?.try(&.as_s?) || "ocawe-agent:latest"
        command = placement["command"]?.try(&.as_s?) || command
        container_cwd = placement["path"]?.try(&.as_s?) || workspace.try(&.[]("path")).try(&.as_s?) || cwd
        host_path = placement["host_path"]?.try(&.as_s?) || workspace.try(&.[]("host_path")).try(&.as_s?)
        write_policy = placement["write_policy"]?.try(&.as_s?) || workspace.try(&.[]("write_policy")).try(&.as_s?) || "write"
        task_name = "ocawe-acp-#{safe_name(@node_id)}-#{safe_name(@run_id)}-#{Random::Secure.hex(4)}"
        tool_args = placement["tool_args"]?.try(&.as_a?).try(&.compact_map { |value| value.as_s? }) || [] of String
        args = tool_args + ["run", "--rm", "-i", "--name", task_name, "--label", "ocawe.acp=true", "--label", "ocawe.workflow=#{@node_id}", "--label", "ocawe.run=#{@run_id}"]
        if entrypoint = placement["entrypoint"]?.try(&.as_s?)
          args += ["--entrypoint", entrypoint]
        end
        if network = placement["network"]?.try(&.as_s?)
          args += ["--network", network]
        end
        if host_path && !host_path.empty? && !container_cwd.empty?
          volume = "#{host_path}:#{container_cwd}"
          volume += ":ro" if write_policy == "read-only" || write_policy == "ro"
          args += ["-v", volume]
        end
        if mounts = placement["mounts"]?.try(&.as_a?)
          mounts.each do |mount|
            config = mount.as_h?
            next unless config
            source = config["host"]?.try(&.as_s?) || config["source"]?.try(&.as_s?)
            target = config["target"]?.try(&.as_s?) || config["path"]?.try(&.as_s?)
            next unless source && target
            mode = config["mode"]?.try(&.as_s?)
            read_only = config["read_only"]?.try(&.as_bool?) || mode == "ro" || mode == "read-only"
            args += ["-v", "#{source}:#{target}#{read_only ? ":ro" : ""}"]
          end
        end
        merged_env = @env.merge(agent_env)
        placement["env"]?.try(&.as_h?).try do |values|
          values.each { |key, value| merged_env[key] = value.as_s? || value.raw.to_s }
        end
        if inherited = placement["inherit_env"]?.try(&.as_a?)
          inherited.each do |name|
            key = name.as_s?
            merged_env[key] = ENV[key] if key && ENV[key]?
          end
        end
        merged_env.each { |key, value| args += ["-e", "#{key}=#{value}"] }
        args += ["-w", container_cwd, image]
        args << command unless placement["entrypoint"]?.try(&.as_s?) == command
        args += command_args
        {tool, args, container_cwd, {} of String => String}
      end

      private def safe_name(value : String) : String
        normalized = value.downcase.gsub(/[^a-z0-9]+/, "-").strip("-")
        normalized = "task" if normalized.empty?
        normalized[0, Math.min(normalized.size, 24)]
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
          content_parts << (update.update.content.try(&.text) || "")
        end

        output["session_id"] = JSON.parse(session_id.to_json)
        output["stop_reason"] = JSON.parse(result.stopReason.to_json)
        output["content"] = JSON.parse(content_parts.join(" ").to_json)
        output["message"] = JSON.parse(content_parts.join(" ").to_json)

        # Include metadata from config
        output["metadata"] = JSON.parse((config["metadata"]?.try(&.as_h?) || {} of String => JSON::Any).to_json)

        output
      end
    end
  end
end
