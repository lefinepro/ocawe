module Ocawe
  module AgentFunctionHandlers
    extend self

    def agent_cliproxy : Ocawe::Workflow::FunctionHandler
      ->(ctx : Ocawe::Workflow::NodeContext) : Ocawe::Workflow::RunnableResult do
        prompt = apply_agent_prompt_contracts(ctx, extract_input_text(ctx.input_data["input"]?))
        system = resolve_string_param(ctx, "system")
        base_url = resolve_string_param(
          ctx,
          "base_url",
          env_keys: ["CLIPROXY_API_BASE", "CLIPROXY_API_URL"],
          default: OcaweCore::AI::CLIProxyChatHelper::DEFAULT_BASE_URL
        ) || OcaweCore::AI::CLIProxyChatHelper::DEFAULT_BASE_URL
        model = resolve_string_param(ctx, "model", env_keys: ["CLIPROXY_MODEL"], default: "qwen3-coder-plus") || "qwen3-coder-plus"
        api_key = resolve_string_param(ctx, "api_key", env_keys: ["CLIPROXY_API_KEY"])

        response = OcaweCore::AI::CLIProxyChatHelper.generate_text(
          provider_name: "cliproxyapi",
          model: model,
          prompt: prompt,
          system: system,
          api_key: api_key,
          base_url: base_url,
        )

        Ocawe::Workflow::AgentResult.new(
          agent_type: "function",
          content: response.text,
          provider: response.provider,
          model: "#{response.provider}/#{response.model}",
          metadata: {
            "engine"   => any("cliproxyapi"),
            "base_url" => any(base_url),
            "model"    => any(model),
          } of String => JSON::Any,
        )
      rescue ex
        Ocawe::Workflow::AgentResult.new(
          agent_type: "function",
          content: "cliproxy error: #{ex.message}",
        )
      end
    end
  end
end
