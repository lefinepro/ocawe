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
        if ENV["COGNICORE_MOCK_LLM"]? == "1"
          text = "[mock open_responses] #{request.prompt}"
          return TextGenerationResponse.new(provider: "open_responses", model: request.model, text: text)
        end

        key = @api_key
        raise "API_KEY is required for OpenResponses provider" unless key

        # Extract user content from prompt, handling both string and structured input
        input = build_openresponses_input(request)

        payload = {
          "model" => any(request.model),
          "input" => any(input),
        } of String => JSON::Any

        response = HTTP::Client.post(
          "#{normalized_base_url}/responses",
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
        TextGenerationResponse.new(provider: "open_responses", model: request.model, text: extract_text(body))
      end

      private def build_openresponses_input(request : TextGenerationRequest) : String
        # Simple case: prompt is plain text
        return request.prompt if request.prompt.starts_with?("{") || request.prompt.starts_with?("[")
        request.prompt
      end

      private def normalized_base_url : String
        base = @base_url.ends_with?("/") ? @base_url[0..-2] : @base_url
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
