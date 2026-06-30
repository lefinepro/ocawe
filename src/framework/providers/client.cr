require "json"
require "./model_ref"
require "./provider"
require "./chat_completions_provider"
require "./openai_provider"
require "./gonka_provider"
require "./cli_provider"

module OcaweCore
  module AI
    class Client
      def initialize(@providers : Hash(String, Provider)? = nil)
      end

      def generate_text(model_spec : String, prompt : String, system : String? = nil, metadata : AnyHash = {} of String => JSON::Any) : TextGenerationResponse
        model = ModelRef.parse(model_spec)
        provider = provider_for(model.provider)
        provider.generate_text(TextGenerationRequest.new(model: model.model, prompt: prompt, system: system, metadata: metadata))
      end

      private def provider_for(name : String) : Provider
        if providers = @providers
          provider = providers[name]?
          raise "unsupported model provider: #{name}" unless provider
          return provider
        end

        case name
        when "chat_completion"
          ChatCompletionProvider.new
        when "open_responses"
          OpenResponsesProvider.new
        when "gonka"
          GonkaProvider.new
        when "cli"
          CliProvider.new
        else
          raise "unsupported model provider: #{name}"
        end
      end
    end
  end
end
