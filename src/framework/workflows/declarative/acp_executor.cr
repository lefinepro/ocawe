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

      def run(
        ref : String,
        input : String,
        config : Hash(String, JSON::Any),
        placement : Hash(String, JSON::Any)? = nil,
        workspace : Hash(String, JSON::Any)? = nil,
      ) : Hash(String, JSON::Any)
        command = resolve_command(ref, config)
        command_args = config["args"]?.try(&.as_a?).try(&.compact_map { |v| v.as_s? }) || [] of String
        cwd = config["cwd"]?.try(&.as_s?) || @cwd
        agent_env = merge_env(config["env"]?)
        task_container = nil

        if placement && placement["mode"]?.try(&.as_s?) == "container"
          command, command_args, cwd, agent_env, task_container = container_command(
            command,
            command_args,
            cwd,
            agent_env,
            placement,
            workspace
          )
        end

        # Initialize agent
        client = ACP::Client.new(command, command_args, agent_env)
        client.start

        # Create session
        session_id = client.create_session(cwd)

        begin
          if model = config["model"]?.try(&.as_s?)
            client.set_model(model, session_id)
          end

          # Send prompt
          result = client.prompt(input)

          # The ACP agent streams the answer as message chunks before the
          # prompt response. Drain the complete queued stream: limiting this
          # to ten updates truncates normal Codex answers.
          updates = client.drain_updates

          # Build output
          output = build_output(session_id, result, updates, config)
          if models = client.session_models
            output["models"] = models
          end
          if options = client.session_config_options
            output["config_options"] = options
          end
          output
        rescue ex : Exception
          STDERR.puts "[acp] node=#{@node_id} command=#{command} failed: #{ex.message || ex.class.name}"
          raise "ACP node '#{ref}' failed: #{ex.message}"
        ensure
          client.close
          remove_task_container(placement, task_container) if placement && task_container
        end
      end

      private def resolve_command(ref : String, config : Hash(String, JSON::Any)) : String
        if explicit_cmd = config["command"]?.try(&.as_s?)
          return explicit_cmd
        end

        # Use ref as the command name
        ref
      end

      private def container_command(
        command : String,
        command_args : Array(String),
        cwd : String,
        agent_env : Hash(String, String),
        placement : Hash(String, JSON::Any),
        workspace : Hash(String, JSON::Any)?,
      ) : {String, Array(String), String, Hash(String, String), String}
        tool = placement["tool"]?.try(&.as_s?) || ENV["OCAWE_CONTAINER_TOOL"]? || "nerdctl"
        image = placement["image"]?.try(&.as_s?) || ENV["OCAWE_AGENT_CONTAINER_IMAGE"]? || "ocawe-agent:latest"
        command = placement["command"]?.try(&.as_s?) || command
        container_cwd = placement["path"]?.try(&.as_s?) ||
                        workspace.try(&.["path"]?).try(&.as_s?) ||
                        ENV["OCAWE_AGENT_WORKSPACE_PATH"]? || cwd
        host_path = placement["host_path"]?.try(&.as_s?) ||
                    workspace.try(&.["host_path"]?).try(&.as_s?) ||
                    ENV["OCAWE_AGENT_HOST_PATH"]?
        write_policy = placement["write_policy"]?.try(&.as_s?) ||
                       workspace.try(&.["write_policy"]?).try(&.as_s?) ||
                       ENV["OCAWE_AGENT_WRITE_POLICY"]? || "write"

        ensure_disk_space!(host_path || cwd, placement)

        task_name = "ocawe-acp-#{safe_name(@node_id)}-#{safe_name(@run_id)}-#{Random::Secure.hex(4)}"
        tool_args = placement["tool_args"]?.try(&.as_a?).try(&.compact_map { |value| value.as_s? }) || [] of String
        args = tool_args + ["run", "--rm", "-i", "--name", task_name,
                            "--label", "ocawe.acp=true",
                            "--label", "ocawe.workflow=#{@node_id}",
                            "--label", "ocawe.run=#{@run_id}"]

        if entrypoint = placement["entrypoint"]?.try(&.as_s?)
          args += ["--entrypoint", entrypoint]
        end

        if network = placement["network"]?.try(&.as_s?) || ENV["OCAWE_AGENT_NETWORK"]?
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
            volume = "#{source}:#{target}#{read_only ? ":ro" : ""}"
            args += ["-v", volume]
          end
        end

        merged_env = @env.merge(agent_env)
        placement["env"]?.try(&.as_h?).try do |values|
          values.each do |key, value|
            merged_env[key] = value.as_s? || value.raw.to_s
          end
        end
        if inherited = placement["inherit_env"]?.try(&.as_a?)
          inherited.each do |name|
            key = name.as_s?
            merged_env[key] = ENV[key] if key && ENV[key]?
          end
        end
        merged_env.each do |key, value|
          args += ["-e", "#{key}=#{value}"]
        end

        args += ["-w", container_cwd, image]
        args << command unless placement["entrypoint"]?.try(&.as_s?) == command
        args += command_args
        {tool, args, container_cwd, {} of String => String, task_name}
      end

      private def remove_task_container(placement : Hash(String, JSON::Any), task_name : String) : Nil
        tool = placement["tool"]?.try(&.as_s?) || ENV["OCAWE_CONTAINER_TOOL"]? || "nerdctl"
        tool_args = placement["tool_args"]?.try(&.as_a?).try(&.compact_map { |value| value.as_s? }) || [] of String
        Process.run(
          tool,
          args: tool_args + ["rm", "-f", task_name],
          input: Process::Redirect::Close,
          output: Process::Redirect::Close,
          error: Process::Redirect::Close,
        )
      rescue ex
        STDERR.puts "[acp] failed to remove task container #{task_name}: #{ex.message || ex.class.name}"
      end

      # A full disk must become a terminal workflow error before the runtime
      # attempts to create a container. The threshold is deliberately part of
      # the Cawfile placement so docker/nerdctl/podman deployments share the
      # same policy without executor-specific defaults.
      private def ensure_disk_space!(path : String, placement : Hash(String, JSON::Any)) : Nil
        minimum = placement["min_free_bytes"]?.try(&.as_i?) ||
                  ENV["OCAWE_MIN_FREE_BYTES"]?.try(&.to_i64?) || 0_i64
        return if minimum <= 0
        output = IO::Memory.new
        status = Process.run("df", args: ["-Pk", path], output: output, error: Process::Redirect::Close)
        raise "disk guard failed for #{path}" unless status.success?
        free_kib = output.to_s.lines[1]?.try(&.split(/\s+/).reject(&.empty?)).try(&.[3]?.try(&.to_i64?)) || 0_i64
        free_bytes = free_kib * 1024_i64
        if free_bytes < minimum
          raise "insufficient disk space for ACP container: #{free_bytes} bytes free, #{minimum} required"
        end
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
          next unless update.update.sessionUpdate == "agent_message_chunk"
          text = update.update.content.try(&.text).to_s
          content_parts << text unless text.empty?
        end

        content = content_parts.join

        output["session_id"] = JSON.parse(session_id.to_json)
        output["stop_reason"] = JSON.parse(result.stopReason.to_json)
        output["content"] = JSON.parse(content.to_json)
        output["message"] = JSON.parse(content.to_json)

        # Include metadata from config
        output["metadata"] = JSON.parse((config["metadata"]?.try(&.as_h?) || {} of String => JSON::Any).to_json)

        output
      end
    end
  end
end
