require "./chat_completions_provider"

module CogniCore
  module AI
    class OpenAPIProvider < ChatCompletionsProvider

      DEFAULT_BASE_URL = "https://alpha-api.col.pub/v1"

      def initialize(@api_key : String? = ENV["OPENAPI_API_KEY"]?, @base_url : String = ENV["OPENAPI_BASE_URL"]? || DEFAULT_BASE_URL)
        super("openapi", @api_key, @base_url)
      end
    end
  end
end
