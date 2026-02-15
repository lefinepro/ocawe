require "./chat_completions_provider"

module CogniCore
  module AI
    class OpenAIProvider < ChatCompletionsProvider

      DEFAULT_BASE_URL = "https://api.openai.com/v1"

      def initialize(@api_key : String? = ENV["OPENAI_API_KEY"]?, @base_url : String = ENV["OPENAI_BASE_URL"]? || DEFAULT_BASE_URL)
        super("openai", @api_key, @base_url)
      end
    end
  end
end
