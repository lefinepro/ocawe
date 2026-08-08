require "json"

module Ocawe
  module Translation
    extend self

    alias AnyHash = Hash(String, JSON::Any)

    enum Format
      ChatCompletions
      OpenResponses
      AnthropicMessages
    end

    def detect(path : String, body : AnyHash) : Format
      normalized_path = path.downcase
      return Format::AnthropicMessages if normalized_path.ends_with?("/messages")
      return Format::OpenResponses if normalized_path.ends_with?("/responses")
      return Format::ChatCompletions if normalized_path.ends_with?("/chat/completions")
      return Format::OpenResponses if body["input"]? && !body["messages"]?
      return Format::ChatCompletions if body["messages"]?

      raise "unable to detect API format"
    end

    # Converts an Anthropic Messages request into the common Chat Completions
    # request shape used by the existing Ocawe execution path.
    def anthropic_request_as_chat(body : AnyHash) : AnyHash
      copy = JSON.parse(body.to_json).as_h
      messages = [] of AnyHash

      if system = copy["system"]?
        system_text = text_from(system)
        unless system_text.empty?
          messages << {
            "role"    => JSON.parse("system".to_json),
            "content" => JSON.parse(system_text.to_json),
          } of String => JSON::Any
        end
      end

      if raw_messages = copy["messages"]?.try(&.as_a?)
        raw_messages.each do |entry|
          hash = entry.as_h
          content = text_from(hash["content"]?)
          messages << {
            "role"    => JSON.parse((hash["role"]?.try(&.as_s?) || "user").to_json),
            "content" => JSON.parse(content.to_json),
          } of String => JSON::Any
        end
      end

      copy["messages"] = JSON.parse(messages.to_json)
      copy["max_tokens"] = copy["max_tokens_to_sample"] if copy["max_tokens"]?.nil? && copy["max_tokens_to_sample"]?
      copy
    end

    # Converts an Ocawe Chat Completions response into Anthropic Messages.
    def chat_response_as_anthropic(completion : AnyHash, request : AnyHash) : AnyHash
      choice = completion["choices"]?.try(&.as_a?).try(&.first?).try(&.as_h?) || {} of String => JSON::Any
      message = choice["message"]?.try(&.as_h?) || {} of String => JSON::Any
      text = message["content"]?.try(&.as_s?) || ""
      usage = completion["usage"]?.try(&.as_h?)
      model = completion["model"]?.try(&.as_s?) || request["model"]?.try(&.as_s?) || "ocawe"

      content = [{
        "type" => JSON.parse("text".to_json),
        "text" => JSON.parse(text.to_json),
      } of String => JSON::Any]

      response = {
        "id"            => completion["id"]? || JSON.parse("msg_#{Random::Secure.hex(12)}".to_json),
        "type"          => JSON.parse("message".to_json),
        "role"          => JSON.parse("assistant".to_json),
        "model"         => JSON.parse(model.to_json),
        "content"       => JSON.parse(content.to_json),
        "stop_reason"   => JSON.parse("end_turn".to_json),
        "stop_sequence" => JSON::Any.new(nil),
      } of String => JSON::Any

      if usage
        response["usage"] = JSON.parse({
          "input_tokens"  => usage["prompt_tokens"]? || JSON.parse("0"),
          "output_tokens" => usage["completion_tokens"]? || JSON.parse("0"),
        }.to_json)
      end
      response
    end

    private def text_from(value : JSON::Any?) : String
      return "" unless value
      return value.as_s if value.as_s?
      if array = value.as_a?
        return array.compact_map { |item| text_from(item) unless item.as_h?.try(&.[]?("type")).try(&.as_s?) == "tool_use" }.join("\n")
      end
      if hash = value.as_h?
        return hash["text"].try(&.as_s?) || hash["content"].try(&.as_s?) || ""
      end
      ""
    end
  end
end
