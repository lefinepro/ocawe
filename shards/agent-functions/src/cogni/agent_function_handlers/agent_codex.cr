module Cogni
  module AgentFunctionHandlers
    extend self

    def agent_codex : Cogni::Workflow::FunctionHandler
      ->(ctx : Cogni::Workflow::NodeContext) : Cogni::Workflow::RunnableResult do
        prompt = apply_agent_prompt_contracts(ctx, extract_input_text(ctx.input_data["input"]?))
        command = resolve_string_param(ctx, "bin", env_keys: ["CODEX_BIN"], default: provider_default_bin("codex")) || provider_default_bin("codex")
        model = resolve_string_param(ctx, "model", env_keys: ["CODEX_MODEL"])
        passthrough = resolve_string_array_param(ctx, "args", env_keys: ["CODEX_ARGS"])
        install_error = ensure_provider_cli_available(ctx, "codex", command)
        if install_error
          return Cogni::Workflow::AgentResult.new(
            agent_type: "function",
            content: "codex install error: #{install_error}",
          )
        end

        args = ["exec"] of String
        if model && !has_model_flag?(passthrough)
          args << "--model"
          args << model
        end
        args.concat(passthrough)
        status, stdout, stderr, resolved_args = run_agent_cli(command, args, prompt, env: provider_env(ctx, "codex"))
        if status.success?
          Cogni::Workflow::AgentResult.new(
            agent_type: "function",
            content: stdout.strip,
            metadata: {
              "engine"  => any("codex"),
              "command" => any("#{command} #{resolved_args.join(" ")}"),
              "model"   => any(model || ""),
            } of String => JSON::Any,
          )
        else
          Cogni::Workflow::AgentResult.new(
            agent_type: "function",
            content: "codex exec failed: #{stderr.strip}",
            metadata: {
              "engine"      => any("codex"),
              "status_code" => any(status.exit_code),
              "model"       => any(model || ""),
            } of String => JSON::Any,
          )
        end
      rescue ex
        Cogni::Workflow::AgentResult.new(
          agent_type: "function",
          content: "codex exec error: #{ex.message}",
        )
      end
    end
  end
end
