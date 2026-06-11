require "json"
require "./model_ref"
require "./provider"
require "./custom_provider_macro"
require "./openai_provider"
require "./cliproxyapi_provider"

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
        when "openai"
          OpenAIProvider.new
        when "cliproxyapi"
          CliproxyAPIProvider.new
        else
          raise "unsupported model provider: #{name}"
        end
      end
    end
  end
end
