require "./provider"

module OcaweCore
  module AI
    class GonkaProvider
      include Provider

      DEFAULT_BASE_URL = "https://api.gonka.ai/v1"

      def initialize(
        @api_key : String? = ENV["GONKA_API_KEY"]?,
        @base_url : String = ENV["GONKA_BASE_URL"]? || DEFAULT_BASE_URL
      )
      end

      def generate_text(request : TextGenerationRequest) : TextGenerationResponse
        if ENV["COGNICORE_MOCK_LLM"]? == "1"
          text = "[mock gonka] #{request.prompt}"
          return TextGenerationResponse.new(provider: "gonka", model: request.model, text: text)
        end

        key = @api_key
        raise "GONKA_API_KEY is required for Gonka provider" unless key

        payload = {
          "model"   => any(request.model),
          "prompt"  => any(request.prompt),
          "system"  => request.system ? any(request.system) : nil,
        }.compact

        response = HTTP::Client.post(
          "#{normalized_base_url}/chat/completions",
          headers: HTTP::Headers{
            "Authorization" => "Bearer #{key}",
            "Content-Type"  => "application/json",
          },
          body: payload.to_json
        )

        unless response.success?
          raise "Gonka request failed (#{response.status_code}): #{response.body}"
        end

        body = JSON.parse(response.body)
        TextGenerationResponse.new(provider: "gonka", model: request.model, text: extract_text(body))
      end

      private def normalized_base_url : String
        base = @base_url.ends_with?("/") ? @base_url[0..-2] : @base_url
        base.ends_with?("/v1") ? base : "#{base}/v1"
      end

      private def extract_text(payload : JSON::Any) : String
        choices = payload["choices"]?.try(&.as_a?)
        return "" unless choices

        first = choices.first?
        return "" unless first

        message = first.as_h?["message"]?.try(&.as_h?)
        return "" unless message

        content = message["content"]?.try(&.as_s?)
        raise "Gonka response is missing generated text" unless content
        content
      end

      private def any(value) : JSON::Any
        JSON.parse(value.to_json)
      end
    end
  end
end
