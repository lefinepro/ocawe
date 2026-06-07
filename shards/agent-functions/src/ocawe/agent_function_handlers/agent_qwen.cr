module Ocawe
  module AgentFunctionHandlers
    extend self

    def agent_qwen : Ocawe::Workflow::FunctionHandler
      ->(ctx : Ocawe::Workflow::NodeContext) : Ocawe::Workflow::RunnableResult do
        prompt = apply_agent_prompt_contracts(ctx, extract_input_text(ctx.input_data["input"]?))
        command = resolve_string_param(ctx, "bin", env_keys: ["QWEN_BIN"], default: provider_default_bin("qwen")) || provider_default_bin("qwen")
        model = resolve_string_param(ctx, "model", env_keys: ["QWEN_MODEL"])
        args = resolve_string_array_param(ctx, "args", env_keys: ["QWEN_ARGS"])
        install_error = ensure_provider_cli_available(ctx, "qwen", command)
        if install_error
          return Ocawe::Workflow::AgentResult.new(
            agent_type: "function",
            content: "qwen install error: #{install_error}",
          )
        end

        if model && !has_model_flag?(args)
          args = args.dup
          args << "--model"
          args << model
        end

        status, stdout, stderr, resolved_args = run_agent_cli(command, args, prompt, env: provider_env(ctx, "qwen"))
        if status.success?
          Ocawe::Workflow::AgentResult.new(
            agent_type: "function",
            content: stdout.strip,
            metadata: {
              "engine"  => any("qwen"),
              "command" => any("#{command} #{resolved_args.join(" ")}"),
              "model"   => any(model || ""),
            } of String => JSON::Any,
          )
        else
          Ocawe::Workflow::AgentResult.new(
            agent_type: "function",
            content: "qwen failed: #{stderr.strip}",
            metadata: {
              "engine"      => any("qwen"),
              "status_code" => any(status.exit_code),
              "model"       => any(model || ""),
            } of String => JSON::Any,
          )
        end
      rescue ex
        Ocawe::Workflow::AgentResult.new(
          agent_type: "function",
          content: "qwen error: #{ex.message}",
        )
      end
    end
  end
end
