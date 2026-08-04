require "json"
require "random/secure"
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
      def initialize(
        @node_id : String,
        @cwd : String = Dir.current,
        @env : Hash(String, String) = {} of String => String,
        @filesystem_policy : ACP::Client::FilesystemPolicy? = nil
      )
      end

      def run(ref : String, input : String, config : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
        command = resolve_command(ref, config)
        command_args = config["args"]?.try(&.as_a?).try(&.compact_map { |v| v.as_s? }) || [] of String
        cwd = config["cwd"]?.try(&.as_s?) || @cwd
        agent_env = merge_env(config["env"]?)
        run_id = task_container_run_id(ref)
        launch = resolve_launch(command, command_args, cwd, agent_env, config["placement"]?, run_id)

        # Initialize agent
        client = ACP::Client.new(launch[:command], launch[:args], launch[:env], @filesystem_policy, launch[:process_cwd])
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
          output["container_run_id"] = JSON.parse(run_id.to_json)
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

      private def resolve_launch(command : String, args : Array(String), cwd : String, env : Hash(String, String), placement : JSON::Any?, run_id : String)
        placement_config = placement.try(&.as_h?) || {} of String => JSON::Any
        placement_image = ENV["OCAWE_AGENT_CONTAINER_IMAGE"]? || placement_config["image"]?.try(&.as_s?)
        placement_host_path = placement_config["host_path"]?.try(&.as_s?) || ENV["OCAWE_AGENT_HOST_PATH"]?
        mode = placement_config["mode"]?.try(&.as_s?) || ENV["OCAWE_AGENT_PLACEMENT"]?

        unless mode
          mode = (placement_image && !placement_image.empty? && placement_host_path && !placement_host_path.empty?) ? "container" : "host"
        end

        case mode
        when "container"
          container_launch(command, args, cwd, env, placement_config, run_id)
        when "host"
          host_launch(command, args, cwd, env, placement_config, run_id)
        else
          raise "unknown ACP placement mode: #{mode}"
        end
      end

      private def host_launch(command : String, args : Array(String), cwd : String, env : Hash(String, String), _placement : Hash(String, JSON::Any), _run_id : String)
        {
          command: command,
          args: args,
          env: env,
          process_cwd: cwd,
        }
      end

      private def container_launch(command : String, args : Array(String), cwd : String, env : Hash(String, String), placement : Hash(String, JSON::Any), run_id : String)
        image = ENV["OCAWE_AGENT_CONTAINER_IMAGE"]? || placement["image"]?.try(&.as_s?)
        raise "container ACP placement requires image" unless image && !image.empty?

        host_path = placement["host_path"]?.try(&.as_s?) || ENV["OCAWE_AGENT_HOST_PATH"]?
        mount_path = placement["path"]?.try(&.as_s?) || ENV["OCAWE_AGENT_WORKSPACE_PATH"]? || cwd
        if workspace = @filesystem_policy
          mount_path = workspace.root
        end
        raise "container ACP placement requires host_path" unless host_path && !host_path.empty?

        write_policy = @filesystem_policy.try(&.write_policy) || "write"
        mount_mode = write_policy == "read_only" ? "ro" : "rw"
        container_tool = placement["tool"]?.try(&.as_s?) || ENV["OCAWE_CONTAINER_TOOL"]? || "docker"
        container_name = task_container_name(run_id)
        container_args = [
          "run",
          "--rm",
          "-i",
          "--name",
          container_name,
          "--label",
          "ocawe.acp.task_run_id=#{run_id}",
          "--label",
          "ocawe.acp.node=#{safe_container_token(@node_id, 48)}",
          "-w",
          cwd,
        ]
        container_args.concat(["-v", "#{File.expand_path(host_path)}:#{mount_path}:#{mount_mode}"])
        env.each do |key, value|
          container_args.concat(["-e", "#{key}=#{value}"])
        end
        container_args << image
        container_args << command
        container_args.concat(args)

        {
          command: container_tool,
          args: container_args,
          env: {} of String => String,
          process_cwd: nil.as(String?),
        }
      end

      private def task_container_run_id(ref : String) : String
        suffix = Random::Secure.hex(6)
        "#{safe_container_token(ref, 48)}-#{Time.utc.to_unix_ms}-#{suffix}"
      end

      private def task_container_name(run_id : String) : String
        "ocawe-acp-#{run_id}"[0, 128]
      end

      private def safe_container_token(value : String, max_size : Int32) : String
        token = value.downcase.gsub(/[^a-z0-9_.-]+/, "-").strip("-")
        token = "task" if token.empty?
        token[0, Math.min(token.size, max_size)]
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
