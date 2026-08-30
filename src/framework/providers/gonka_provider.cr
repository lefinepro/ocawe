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
        if ENV["COGNICORE_MOCK_LLM"]? == "1" && request.api_key.nil?
          text = "[mock gonka] #{request.prompt}"
          return TextGenerationResponse.new(provider: "gonka", model: request.model, text: text)
        end

        key = request.api_key || @api_key
        raise "GONKA_API_KEY is required for Gonka provider" unless key

        payload = {
          "model"   => any(request.model),
          "prompt"  => any(request.prompt),
          "system"  => request.system ? any(request.system) : nil,
        }.compact

        effective_base = request.base_url || @base_url
        response = HTTP::Client.post(
          "#{normalized_base_url(effective_base)}/chat/completions",
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
        TextGenerationResponse.new(
          provider: "gonka",
          model: request.model,
          text: extract_text(body),
          usage: TokenUsage.from_payload(body)
        )
      end

      private def normalized_base_url(base : String) : String
        base = base.ends_with?("/") ? base[0..-2] : base
        if (idx = base.index("/v1/"))
          base = base[0, idx + 3]
        end
        base.ends_with?("/v1") ? base : "#{base}/v1"
      end

      private def extract_text(payload : JSON::Any) : String
        choices = payload["choices"]?.try(&.as_a?)
        return "" unless choices

      first = choices.first?
      return "" unless first

      message = first.as_h?.try(&.["message"]?).try(&.as_h?)
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
