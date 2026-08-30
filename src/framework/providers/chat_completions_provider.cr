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

        copy_metadata(payload, request.metadata, "temperature")
        copy_metadata(payload, request.metadata, "max_tokens")
        copy_metadata(payload, request.metadata, "max_completion_tokens")

        if tools = request.tools
          payload["tools"] = JSON.parse(tools.to_json)
        end

        effective_base = request.base_url || @base_url
        response = post_json(
          "#{normalized_base_url(effective_base)}/chat/completions",
          key,
          payload.to_json,
          request_timeout(request.metadata)
        )

        unless response.success?
          raise "ChatCompletion request failed (#{response.status_code}): #{response.body}"
        end

        body = JSON.parse(response.body)
        text, tool_calls = extract_result(body)
        TextGenerationResponse.new(
          provider: "chat_completion",
          model: request.model,
          text: text,
          tool_calls: tool_calls,
          usage: TokenUsage.from_payload(body)
        )
      end

      private def build_messages(request : TextGenerationRequest) : Array(JSON::Any)
        if raw_messages = request.messages
          return raw_messages.map { |m| sanitize_message(m) }
        end

        messages = [] of JSON::Any
        if system = request.system
          messages << JSON.parse({"role" => "system", "content" => system}.to_json)
        end
        messages << JSON.parse({"role" => "user", "content" => request.prompt}.to_json)
        messages
      end

      private def sanitize_message(msg : JSON::Any) : JSON::Any
        hash = msg.as_h?
        return msg unless hash

        role = hash["role"]?.try(&.as_s?)
        content = hash["content"]?
        tool_calls = hash["tool_calls"]?

        # Ensure content is never null in assistant messages with tool_calls
        if role == "assistant" && tool_calls
          is_null = content.nil? || content.raw.nil?
          if is_null
            new_hash = hash.dup
            new_hash["content"] = JSON::Any.new("")
            return JSON::Any.new(new_hash)
          end
        end

        msg
      end

      private def normalized_base_url(base : String) : String
        base = base.ends_with?("/") ? base[0..-2] : base
        if (idx = base.index("/v1/"))
          base = base[0, idx + 3]
        end
        base.ends_with?("/v1") ? base : "#{base}/v1"
      end

      private def post_json(url : String, key : String, body : String, timeout : Time::Span) : HTTP::Client::Response
        uri = URI.parse(url)
        HTTP::Client.new(uri) do |client|
          client.connect_timeout = timeout
          client.read_timeout = timeout
          client.write_timeout = timeout
          client.post(
            uri.request_target,
            headers: HTTP::Headers{
              "Authorization" => "Bearer #{key}",
              "Content-Type"  => "application/json",
            },
            body: body
          )
        end
      end

      private def request_timeout(metadata : AnyHash) : Time::Span
        seconds = metadata_number(metadata["timeout_seconds"]?) || metadata_number(metadata["timeout"]?) || 20.0
        seconds = 1.0 if seconds < 1.0
        seconds.seconds
      end

      private def metadata_number(value : JSON::Any?) : Float64?
        return nil unless value
        value.as_f? || value.as_i?.try(&.to_f) || value.as_s?.try(&.to_f?)
      end

      private def copy_metadata(payload : Hash(String, JSON::Any), metadata : AnyHash, key : String) : Nil
        value = metadata[key]?
        payload[key] = value if value
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
