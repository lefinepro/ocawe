module OcaweCore
  module AI
    # Defines a custom OpenAI-compatible provider class under OcaweCore::AI.
    #
    # Example:
    #   OcaweCore::AI.create_custom_provider(
    #     AcmeProvider,
    #     "acme",
    #     "ACME_BASE_URL",
    #     "ACME_API_KEY",
    #     "https://acme.example/v1"
    #   )
    macro create_custom_provider(class_name, provider_name, base_url_env, api_key_env, default_base_url = "http://127.0.0.1:8080")
      class ::OcaweCore::AI::{{class_name.id}}
        include ::OcaweCore::AI::Provider

        DEFAULT_BASE_URL = {{default_base_url}}

        def initialize(
          @api_key : String? = ENV[{{api_key_env}}]?,
          @base_url : String = ENV[{{base_url_env}}]? || DEFAULT_BASE_URL
        )
        end

        def generate_text(request : ::OcaweCore::AI::TextGenerationRequest) : ::OcaweCore::AI::TextGenerationResponse
          ::OcaweCore::AI::CLIProxyChatHelper.generate_text(
            provider_name: {{provider_name}},
            model: request.model,
            prompt: request.prompt,
            system: request.system,
            api_key: @api_key,
            base_url: @base_url,
          )
        end
      end
    end
  end
end
