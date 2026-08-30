require "./chat_completions_provider"

module OcaweCore
  module AI
    class OpenResponsesProvider
      include Provider

      DEFAULT_BASE_URL = "https://api.openai.com/v1"

      def initialize(
        @api_key : String? = ENV["OPENAI_API_KEY"]?,
        @base_url : String = ENV["OPENAI_BASE_URL"]? || DEFAULT_BASE_URL
      )
      end

      def generate_text(request : TextGenerationRequest) : TextGenerationResponse
        if ENV["COGNICORE_MOCK_LLM"]? == "1" && request.api_key.nil?
          text = "[mock open_responses] #{request.prompt}"
          return TextGenerationResponse.new(provider: "open_responses", model: request.model, text: text)
        end

        key = request.api_key || @api_key
        raise "API_KEY is required for OpenResponses provider" unless key

        # Extract user content from prompt, handling both string and structured input
        input = build_openresponses_input(request)

        payload = {
          "model" => any(request.model),
          "input" => any(input),
        } of String => JSON::Any

        effective_base = request.base_url || @base_url
        response = HTTP::Client.post(
          "#{normalized_base_url(effective_base)}/responses",
          headers: HTTP::Headers{
            "Authorization" => "Bearer #{key}",
            "Content-Type"  => "application/json",
          },
          body: payload.to_json
        )

        unless response.success?
          raise "OpenResponses request failed (#{response.status_code}): #{response.body}"
        end

        body = JSON.parse(response.body)
        TextGenerationResponse.new(
          provider: "open_responses",
          model: request.model,
          text: extract_text(body),
          usage: TokenUsage.from_payload(body)
        )
      end

      private def build_openresponses_input(request : TextGenerationRequest) : String
        # Simple case: prompt is plain text
        return request.prompt if request.prompt.starts_with?("{") || request.prompt.starts_with?("[")
        request.prompt
      end

      private def normalized_base_url(base : String) : String
        base = base.ends_with?("/") ? base[0..-2] : base
        if (idx = base.index("/v1/"))
          base = base[0, idx + 3]
        end
        base.ends_with?("/v1") ? base : "#{base}/v1"
      end

      private def extract_text(payload : JSON::Any) : String
        output = payload["output"]?.try(&.as_a?)
        return "" unless output

        text_parts = output.compact_map do |item|
          hash = item.as_h?
          next nil unless hash
          hash["text"]?.try(&.as_s?)
        end
        result = text_parts.join("\n")
        raise "OpenResponses response is missing generated text" if result.empty?
        result
      end

      private def any(value) : JSON::Any
        JSON.parse(value.to_json)
      end
    end
  end
end
