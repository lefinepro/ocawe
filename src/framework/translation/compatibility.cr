require "json"

module Ocawe
  module Translation
    extend self

    enum Format
      ChatCompletions
      OpenResponses
      AnthropicMessages
    end

    struct ContentBlock
      include JSON::Serializable
      property type : String
      property text : String?

      def initialize(@type : String, @text : String? = nil)
      end
    end

    struct Message
      include JSON::Serializable
      property role : String
      property content : String | Array(ContentBlock)

      def initialize(@role : String, @content : String | Array(ContentBlock))
      end
    end

    struct AnthropicRequest
      include JSON::Serializable
      property model : String?
      property messages : Array(Message) = [] of Message
      property system : String | Array(ContentBlock)?
      property max_tokens : Int32?
      property max_tokens_to_sample : Int32?
      property stream : Bool?
    end

    struct ChatRequest
      include JSON::Serializable
      property model : String?
      property messages : Array(Message)
      property max_tokens : Int32?
      property stream : Bool?

      def initialize(@model : String?, @messages : Array(Message), @max_tokens : Int32? = nil, @stream : Bool? = nil)
      end
    end

    struct ChatUsage
      include JSON::Serializable
      property prompt_tokens : Int32
      property completion_tokens : Int32
    end

    struct ChatChoice
      include JSON::Serializable
      property message : Message
      property finish_reason : String?
    end

    struct ChatCompletion
      include JSON::Serializable
      property id : String?
      property model : String?
      property choices : Array(ChatChoice)
      property usage : ChatUsage?
    end

    struct AnthropicUsage
      include JSON::Serializable
      property input_tokens : Int32
      property output_tokens : Int32

      def initialize(@input_tokens : Int32, @output_tokens : Int32)
      end
    end

    struct AnthropicResponse
      include JSON::Serializable
      property id : String
      property type : String
      property role : String
      property model : String
      property content : Array(ContentBlock)
      property stop_reason : String?
      property stop_sequence : String?
      property usage : AnthropicUsage?

      def initialize(
        @id : String,
        @type : String,
        @role : String,
        @model : String,
        @content : Array(ContentBlock),
        @stop_reason : String?,
        @stop_sequence : String?,
        @usage : AnthropicUsage?,
      )
      end
    end

    def detect(path : String, body : String) : Format
      normalized_path = path.downcase
      return Format::AnthropicMessages if normalized_path.ends_with?("/messages")
      return Format::OpenResponses if normalized_path.ends_with?("/responses")
      return Format::ChatCompletions if normalized_path.ends_with?("/chat/completions")

      parsed = JSON.parse(body)
      return Format::OpenResponses if parsed["input"]? && !parsed["messages"]?
      return Format::ChatCompletions if parsed["messages"]?

      raise "unable to detect API format"
    end

    def anthropic_request_as_chat(body : String) : String
      request = AnthropicRequest.from_json(body)
      messages = [] of Message

      if system = request.system
        system_text = text_from(system)
        messages << Message.new(role: "system", content: system_text) unless system_text.empty?
      end

      request.messages.each do |message|
        messages << Message.new(role: message.role, content: text_from(message.content))
      end
      normalized = ChatRequest.new(
        model: request.model,
        messages: messages,
        max_tokens: request.max_tokens || request.max_tokens_to_sample,
        stream: request.stream,
      )
      normalized.to_json
    end

    # Normalize any supported request format to the internal Chat Completions
    # envelope. This is deliberately JSON based so workflows and plugins can
    # use it without depending on one provider's wire structs.
    def request_as_chat(path : String, body : String) : String
      case detect(path, body)
      when Format::ChatCompletions
        body
      when Format::AnthropicMessages
        anthropic_request_as_chat(body)
      when Format::OpenResponses
        open_responses_request_as_chat(body)
      else
        raise "unsupported translation format"
      end
    end

    def chat_response_as_anthropic(completion : String, request : String) : String
      response = ChatCompletion.from_json(completion)
      input = AnthropicRequest.from_json(request)
      choice = response.choices.first?
      text = choice ? text_from(choice.message.content) : ""
      stop_reason = choice.try(&.finish_reason) == "tool_calls" ? "tool_use" : "end_turn"
      output = AnthropicResponse.new(
        id: response.id || "msg_#{Random::Secure.hex(12)}",
        type: "message",
        role: "assistant",
        model: response.model.to_s.empty? ? input.model.to_s : response.model.to_s,
        content: [ContentBlock.new(type: "text", text: text)],
        stop_reason: stop_reason,
        stop_sequence: nil,
        usage: response.usage.try { |usage| AnthropicUsage.new(input_tokens: usage.prompt_tokens, output_tokens: usage.completion_tokens) },
      )
      output.to_json
    end

    def open_responses_request_as_chat(body : String) : String
      parsed = JSON.parse(body).as_h
      messages = [] of JSON::Any
      if input = parsed["input"]?
        if text = input.as_s?
          messages << message_json("user", text)
        elsif items = input.as_a?
          items.each do |item|
            if text = item.as_s?
              messages << message_json("user", text)
            elsif hash = item.as_h?
              role = hash["role"]?.try(&.as_s?) || "user"
              content = hash["content"]?.try(&.as_s?) || hash["text"]?.try(&.as_s?) || hash["input_text"]?.try(&.as_s?)
              messages << message_json(role, content) if content && !content.empty?
            end
          end
        end
      end
      parsed["messages"] = JSON::Any.new(messages)
      parsed.delete("input")
      parsed.to_json
    end

    def chat_response_as_open_responses(completion : String, request : String = "{}") : String
      response = JSON.parse(completion).as_h
      request_json = JSON.parse(request).as_h
      choices = response["choices"]?.try(&.as_a?) || [] of JSON::Any
      choice = choices.first?.try(&.as_h?) || {} of String => JSON::Any
      message = choice["message"]?.try(&.as_h?) || {} of String => JSON::Any
      text = message["content"]?.try(&.as_s?) || ""
      model = response["model"]?.try(&.as_s?) || request_json["model"]?.try(&.as_s?) || "unknown"
      id = response["id"]?.try(&.as_s?) || "resp_#{Random::Secure.hex(12)}"
      finish = choice["finish_reason"]?.try(&.as_s?) || "stop"
      output = {
        "id" => id,
        "object" => "response",
        "created_at" => response["created"]?.try(&.as_i64?) || Time.utc.to_unix,
        "status" => "completed",
        "model" => model,
        "output" => [{
          "type" => "message",
          "role" => "assistant",
          "content" => [{"type" => "output_text", "text" => text}],
        }],
        "output_text" => text,
        "finish_reason" => finish,
      }
      output.to_json
    end

    def open_responses_response_as_chat(body : String, request : String = "{}") : String
      parsed = JSON.parse(body).as_h
      request_json = JSON.parse(request).as_h
      text = parsed["output_text"]?.try(&.as_s?) || extract_output_text(parsed["output"]?)
      model = parsed["model"]?.try(&.as_s?) || request_json["model"]?.try(&.as_s?)
      {
        "id" => parsed["id"]?.try(&.as_s?) || "chatcmpl-#{Random::Secure.hex(12)}",
        "object" => "chat.completion",
        "created" => parsed["created_at"]?.try(&.as_i64?) || Time.utc.to_unix,
        "model" => model || "unknown",
        "choices" => [{
          "index" => 0,
          "message" => {"role" => "assistant", "content" => text},
          "finish_reason" => parsed["status"]?.try(&.as_s?) == "completed" ? "stop" : "length",
        }],
      }.to_json
    end

    private def text_from(content : String | Array(ContentBlock)) : String
      return content if content.is_a?(String)
      content.compact_map(&.text).join("\n")
    end

    private def message_json(role : String, content : String) : JSON::Any
      JSON.parse({"role" => role, "content" => content}.to_json)
    end

    private def extract_output_text(output : JSON::Any?) : String
      return "" unless output
      items = output.as_a? || [] of JSON::Any
      items.flat_map do |item|
        hash = item.as_h?
        next [] of String unless hash
        content = hash["content"]?.try(&.as_a?) || [] of JSON::Any
        content.compact_map { |part| part.as_h?.try(&.["text"]?).try(&.as_s?) }
      end.join("\n")
    end
  end
end
