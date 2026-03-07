module Cogni
  module AgentFunctionHandlers
    extend self

    def agent_opencode : Cogni::Workflow::FunctionHandler
      ->(ctx : Cogni::Workflow::NodeContext) : Cogni::Workflow::RunnableResult do
        prompt = extract_input_text(ctx.input_data["input"]?)
        command = resolve_string_param(ctx, "bin", env_keys: ["OPENCODE_BIN"], default: provider_default_bin("opencode")) || provider_default_bin("opencode")
        model = resolve_string_param(ctx, "model", env_keys: ["OPENCODE_MODEL"])
        args = resolve_string_array_param(ctx, "args", env_keys: ["OPENCODE_ARGS"])
        install_error = ensure_provider_cli_available(ctx, "opencode", command)
        if install_error
          return Cogni::Workflow::AgentResult.new(
            agent_type: "function",
            content: "opencode install error: #{install_error}",
          )
        end

        if model && !has_model_flag?(args)
          args = args.dup
          args << "--model"
          args << model
        end
        status, stdout, stderr, resolved_args = run_agent_cli(command, args, prompt, env: provider_env(ctx, "opencode"))
        content = status.success? ? stdout.strip : "opencode failed: #{stderr.strip}"

        Cogni::Workflow::AgentResult.new(
          agent_type: "function",
          content: content,
          metadata: {
            "engine"      => any("opencode"),
            "command"     => any("#{command} #{resolved_args.join(" ")}"),
            "status_code" => any(status.exit_code),
            "model"       => any(model || ""),
          } of String => JSON::Any,
        )
      rescue ex
        Cogni::Workflow::AgentResult.new(
          agent_type: "function",
          content: "opencode error: #{ex.message}",
        )
      end
    end
  end
end
