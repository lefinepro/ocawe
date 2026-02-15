require "./cliproxy_chat_helper"

module CogniCore
  module AI
    class CliproxyAPIProvider
      include Provider

      DEFAULT_BASE_URL = CLIProxyChatHelper::DEFAULT_BASE_URL

      def initialize(
        @api_key : String? = ENV["CLIPROXY_API_KEY"]?,
        @base_url : String = ENV["CLIPROXY_API_BASE"]? || ENV["CLIPROXY_API_URL"]? || DEFAULT_BASE_URL
      )
      end

      def generate_text(request : TextGenerationRequest) : TextGenerationResponse
        CLIProxyChatHelper.generate_text(
          provider_name: "cliproxyapi",
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
