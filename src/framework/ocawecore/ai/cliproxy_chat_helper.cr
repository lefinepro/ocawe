require "http/client"
require "json"

module OcaweCore
  module AI
    module CLIProxyChatHelper
      DEFAULT_BASE_URL = "http://127.0.0.1:8080"

      def self.generate_text(
        provider_name : String,
        model : String,
        prompt : String,
        system : String? = nil,
        api_key : String? = nil,
        base_url : String = DEFAULT_BASE_URL
      ) : TextGenerationResponse
        if ENV["COGNICORE_MOCK_LLM"]? == "1"
          text = "[mock #{provider_name}] #{prompt}"
          return TextGenerationResponse.new(provider: provider_name, model: model, text: text)
        end

        payload = {
          "model"    => any(model),
          "messages" => any(build_messages(prompt, system)),
        } of String => JSON::Any

        headers = HTTP::Headers{"Content-Type" => "application/json"}
        headers["Authorization"] = "Bearer #{api_key}" if api_key

        response = HTTP::Client.post(
          "#{normalized_base_url(base_url)}/chat/completions",
          headers: headers,
          body: payload.to_json
        )

        unless response.success?
          raise "#{provider_name} request failed (#{response.status_code}): #{response.body}"
        end

        text = parse_openai_chat_content(response.body)
        raise "#{provider_name} response is missing generated text" unless text

        TextGenerationResponse.new(provider: provider_name, model: model, text: text)
      end

      private def self.build_messages(prompt : String, system : String?) : Array(Hash(String, JSON::Any))
        messages = [] of Hash(String, JSON::Any)
        if system
          messages << {"role" => any("system"), "content" => any(system)}
        end
        messages << {"role" => any("user"), "content" => any(prompt)}
        messages
      end

      private def self.normalized_base_url(base_url : String) : String
        base = base_url.ends_with?("/") ? base_url[0..-2] : base_url
        base.ends_with?("/v1") ? base : "#{base}/v1"
      end

      private def self.parse_openai_chat_content(body : String) : String?
        parsed = JSON.parse(body).as_h?
        return nil unless parsed

        choices = parsed["choices"]?.try(&.as_a?)
        return nil unless choices && !choices.empty?

        first = choices[0].as_h?
        return nil unless first

        message = first["message"]?.try(&.as_h?)
        return nil unless message

        if content = message["content"]?.try(&.as_s?)
          return content
        end

        parts = message["content"]?.try(&.as_a?)
        return nil unless parts

        joined = parts.compact_map { |part| part.as_h?.try(&.["text"]?).try(&.as_s?) }.join("\n")
        joined.empty? ? nil : joined
      rescue
        nil
      end

      private def self.any(value) : JSON::Any
        JSON.parse(value.to_json)
      end
    end
  end
end
