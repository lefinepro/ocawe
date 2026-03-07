module Cogni
  module AgentFunctionHandlers
    extend self

    private def parse_session_id(body : String) : String?
      parsed = JSON.parse(body).as_h?
      return nil unless parsed
      parsed["id"]?.try(&.as_s?) ||
        parsed["sessionID"]?.try(&.as_s?) ||
        parsed["session_id"]?.try(&.as_s?) ||
        parsed["session"]?.try(&.as_h?).try(&.["id"]?).try(&.as_s?)
    rescue
      nil
    end

    private def parse_opencode_message_content(body : String) : String?
      parsed = JSON.parse(body).as_h?
      return nil unless parsed
      content = parsed["content"]?.try(&.as_s?)
      return content if content
      text = parsed["text"]?.try(&.as_s?)
      return text if text

      parts = parsed["parts"]?.try(&.as_a?)
      if parts
        joined = parts.compact_map { |part| part.as_h?.try(&.["text"]?).try(&.as_s?) }.join("\n")
        return joined unless joined.empty?
      end

      message = parsed["message"]?.try(&.as_h?)
      if message
        direct = message["content"]?.try(&.as_s?) || message["text"]?.try(&.as_s?)
        return direct if direct
        msg_parts = message["parts"]?.try(&.as_a?)
        if msg_parts
          joined = msg_parts.compact_map { |part| part.as_h?.try(&.["text"]?).try(&.as_s?) }.join("\n")
          return joined unless joined.empty?
        end
      end
      nil
    rescue
      nil
    end

    private def any(value) : JSON::Any
      JSON.parse(value.to_json)
    end
  end
end
