require "http/client"
require "json"

module CogniCore
  module AI
    class OpenAPIProvider
      include Provider

      DEFAULT_BASE_URL = "https://alpha-api.col.pub/v1"

      def initialize(@api_key : String? = ENV["OPENAPI_API_KEY"]?, @base_url : String = ENV["OPENAPI_BASE_URL"]? || DEFAULT_BASE_URL)
      end

      def generate_text(request : TextGenerationRequest) : TextGenerationResponse
        if ENV["COGNICORE_MOCK_LLM"]? == "1"
          text = "[mock openapi] #{request.prompt}"
          return TextGenerationResponse.new(provider: "openapi", model: request.model, text: text)
        end

        key = @api_key
        raise "OPENAPI_API_KEY is required" unless key

        payload_messages = [] of Hash(String, JSON::Any)
        if system = request.system
          payload_messages << {
            "role" => any("system"),
            "content" => any(system),
          }
        end
        payload_messages << {
          "role" => any("user"),
          "content" => any(request.prompt),
        }

        payload = {
          "model" => any(request.model),
          "messages" => any(payload_messages),
        } of String => JSON::Any

        base = @base_url.ends_with?("/") ? @base_url[0..-2] : @base_url
        base = "#{base}/v1" unless base.ends_with?("/v1")
        endpoint = "#{base}/chat/completions"

        headers = HTTP::Headers{
          "Authorization" => "Bearer #{key}",
          "Content-Type" => "application/json",
        }

        response = HTTP::Client.post(endpoint, headers: headers, body: payload.to_json)
        unless response.success?
          raise "openapi request failed (#{response.status_code}): #{response.body}"
        end

        body = JSON.parse(response.body)
        text = extract_text(body)
        TextGenerationResponse.new(provider: "openapi", model: request.model, text: text)
      end

      private def extract_text(payload : JSON::Any) : String
        choices = payload["choices"]?.try(&.as_a?)
        message = choices.try(&.first?)
        content = message.try(&.["message"]?).try(&.as_h?)

        value = content.try(&.["content"]?)
        if text = value.try(&.as_s?)
          return text
        end

        if parts = value.try(&.as_a?)
          rendered = parts.compact_map do |part|
            part.as_h?.try(&.["text"]?).try(&.as_s?)
          end
          return rendered.join("\n") unless rendered.empty?
        end

        raise "openapi response is missing generated text"
      end

      private def any(value) : JSON::Any
        JSON.parse(value.to_json)
      end
    end
  end
end
