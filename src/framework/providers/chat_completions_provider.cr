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
        if ENV["COGNICORE_MOCK_LLM"]? == "1" && request.api_key.nil?
          text = "[mock chat_completion] #{request.prompt}"
          return TextGenerationResponse.new(provider: "chat_completion", model: request.model, text: text)
        end

        key = request.api_key || @api_key
        raise "API_KEY is required for ChatCompletion provider" unless key

        payload = {
          "model" => any(request.model),
          "messages" => any(build_messages(request)),
        } of String => JSON::Any

        if tools = request.tools
          payload["tools"] = JSON.parse(tools.to_json)
        end

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
          raise "ChatCompletion request failed (#{response.status_code}): #{response.body}"
        end

        body = JSON.parse(response.body)
        text, tool_calls = extract_result(body)
        TextGenerationResponse.new(provider: "chat_completion", model: request.model, text: text, tool_calls: tool_calls)
      end

      private def build_messages(request : TextGenerationRequest) : Array(JSON::Any)
        if raw_messages = request.messages
          return raw_messages
        end

        messages = [] of JSON::Any
        if system = request.system
          messages << JSON.parse({"role" => "system", "content" => system}.to_json)
        end
        messages << JSON.parse({"role" => "user", "content" => request.prompt}.to_json)
        messages
      end

      private def normalized_base_url(base : String) : String
        base = base.ends_with?("/") ? base[0..-2] : base
        if (idx = base.index("/v1/"))
          base = base[0, idx + 3]
        end
        base.ends_with?("/v1") ? base : "#{base}/v1"
      end

      private def extract_result(payload : JSON::Any) : Tuple(String, Array(JSON::Any)?)
        choices = payload["choices"]?.try(&.as_a?)
        return {"", nil} unless choices && choices.size > 0

        message = choices.first["message"]?.try(&.as_h?)
        return {"", nil} unless message

        content = message["content"]?
        text = if content_value = content
                 if s = content_value.as_s?
                   s
                 elsif parts = content_value.as_a?
                   parts.compact_map { |part| part.as_h?.try(&.["text"]?).try(&.as_s?) }.join("\n")
                 else
                   content_value.to_json
                 end
               else
                 ""
               end

        tool_calls = message["tool_calls"]?.try(&.as_a?)
        return {text, nil} unless tool_calls && tool_calls.size > 0

        {text, tool_calls}
      end

      private def any(value) : JSON::Any
        JSON.parse(value.to_json)
      end
    end
  end
end
