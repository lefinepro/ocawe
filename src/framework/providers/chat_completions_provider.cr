require "http/client"
require "json"
require "./provider"

module OcaweCore
  module AI
    class ChatCompletionProvider
      include Provider

      DEFAULT_BASE_URL = "https://api.openai.com/v1"

      def initialize(
        @api_key : String? = ENV["OPENAI_API_KEY"]?,
        @base_url : String = ENV["OPENAI_BASE_URL"]? || DEFAULT_BASE_URL
      )
      end

      def generate_text(request : TextGenerationRequest) : TextGenerationResponse
        if ENV["COGNICORE_MOCK_LLM"]? == "1"
          text = "[mock chat_completion] #{request.prompt}"
          return TextGenerationResponse.new(provider: "chat_completion", model: request.model, text: text)
        end

        key = @api_key
        raise "API_KEY is required for ChatCompletion provider" unless key

        payload = {
          "model" => any(request.model),
          "messages" => any(build_messages(request)),
        } of String => JSON::Any

        response = HTTP::Client.post(
          "#{normalized_base_url}/chat/completions",
          headers: HTTP::Headers{
            "Authorization" => "Bearer #{key}",
            "Content-Type"  => "application/json",
          },
          body: payload.to_json
        )

        unless response.success?
          raise "ChatCompletion request failed (#{response.status_code}): #{response.body}"
        end

        body = JSON.parse(response.body)
        TextGenerationResponse.new(provider: "chat_completion", model: request.model, text: extract_text(body))
      end

      private def build_messages(request : TextGenerationRequest) : Array(Hash(String, JSON::Any))
        messages = [] of Hash(String, JSON::Any)
        if system = request.system
          messages << {"role" => any("system"), "content" => any(system)}
        end
        messages << {"role" => any("user"), "content" => any(request.prompt)}
        messages
      end

      private def normalized_base_url : String
        base = @base_url.ends_with?("/") ? @base_url[0..-2] : @base_url
        base.ends_with?("/v1") ? base : "#{base}/v1"
      end

      private def extract_text(payload : JSON::Any) : String
        choices = payload["choices"]?.try(&.as_a?)
        message = choices.try(&.first?)
        content = message.try(&.["message"]? ).try(&.as_h?)

        value = content.try(&.["content"]?)
        if text = value.try(&.as_s?)
          return text
        end

        if parts = value.try(&.as_a?)
          rendered = parts.compact_map do |part|
            part.as_h?.try(&.["text"]? ).try(&.as_s?)
          end
          return rendered.join("\n") unless rendered.empty?
        end

        raise "ChatCompletion response is missing generated text"
      end

      private def any(value) : JSON::Any
        JSON.parse(value.to_json)
      end
    end
  end
end
