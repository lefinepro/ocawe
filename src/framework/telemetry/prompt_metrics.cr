require "json"
require "../telemetry"

module Ocawe
  module PromptMetrics
    extend self

    def label(value : String?, fallback : String = "unknown", max : Int32 = 96) : String
      raw = value.to_s.strip
      raw = fallback if raw.empty?
      cleaned = raw
        .gsub(/^@/, "")
        .gsub(/[^a-zA-Z0-9._ -]+/, "-")
        .gsub(/\s+/, " ")
        .gsub(/^-+|-+$/, "")
        .strip
      cleaned = fallback if cleaned.empty?
      cleaned[0, Math.min(cleaned.size, max)]
    end

    def prompt_label(prompt : String) : String
      first_line = prompt.lines.first?.to_s.strip
      label(first_line.sub(/\Aname:[^\s]+\s*/i, "").strip, "empty", 96)
    end

    def profile_label(metadata : Hash(String, JSON::Any) = {} of String => JSON::Any) : String
      label(first_string(metadata, ["profile", "user", "username", "account"]), "anon", 80)
    end

    def session_label(metadata : Hash(String, JSON::Any) = {} of String => JSON::Any) : String
      label(first_string(metadata, ["session", "session_id", "conversation_id", "request_id"]), "anon", 48)
    end

    def message_count(messages : Array(JSON::Any)?) : Int32
      messages.try(&.size) || 0
    end

    def context_chars(prompt : String, system : String?, messages : Array(JSON::Any)?) : Int32
      total = prompt.size + system.to_s.size
      if items = messages
        items.each { |message| total += json_text_size(message) }
      end
      total
    end

    def response_tokens(text : String) : Int32
      text.split(/\s+/).reject(&.empty?).size
    end

    def record(
      source : String,
      provider : String,
      model : String,
      prompt : String,
      status : String,
      latency_ms : Float64,
      context_messages : Int32,
      context_chars : Int32,
      output_tokens : Int32 = 0,
      profile : String = "anon",
      session : String = "anon",
      time_to_response_ms : Float64? = nil
    ) : Nil
      labels = {
        "source"   => label(source, "unknown", 48),
        "provider" => label(provider, "unknown", 80),
        "model"    => label(model, "unknown", 96),
        "profile"  => label(profile, "anon", 80),
        "session"  => label(session, "anon", 48),
        "prompt"   => prompt_label(prompt),
        "status"   => label(status, "unknown", 32),
      } of String => Telemetry::AttributeValue

      Telemetry.increment("chat.prompt.requests.total", attributes: labels)
      Telemetry.histogram("chat.prompt.context.messages", context_messages, "1", labels)
      Telemetry.histogram("chat.prompt.context.chars", context_chars, "By", labels)
      Telemetry.histogram("chat.prompt.latency_ms", latency_ms, "ms", labels)
      Telemetry.histogram("chat.prompt.time_to_response_ms", time_to_response_ms, "ms", labels) if time_to_response_ms
      if output_tokens > 0
        Telemetry.increment("chat.prompt.output_tokens.total", output_tokens, "1", labels)
        tokens_per_second = output_tokens.to_f64 / {latency_ms / 1000.0, 0.001}.max
        Telemetry.histogram("chat.prompt.tokens_per_second", tokens_per_second, "1/s", labels)
      end

      Telemetry.log(
        status == "success" ? "info" : "error",
        "prompt generation completed",
        labels.merge({
          "context_messages"   => context_messages,
          "context_chars"      => context_chars,
          "output_tokens"      => output_tokens,
          "latency_ms"         => latency_ms,
          "time_to_response_ms" => time_to_response_ms || 0.0,
        } of String => Telemetry::AttributeValue)
      )
    end

    private def first_string(metadata : Hash(String, JSON::Any), keys : Array(String)) : String?
      keys.each do |key|
        value = metadata[key]?.try(&.as_s?)
        return value if value && !value.strip.empty?
      end
      nil
    end

    private def json_text_size(value : JSON::Any) : Int32
      if string = value.as_s?
        string.size
      elsif hash = value.as_h?
        hash.reduce(0) { |total, entry| total + json_text_size(entry[1]) }
      elsif array = value.as_a?
        array.reduce(0) { |total, item| total + json_text_size(item) }
      else
        value.to_json.size
      end
    end
  end
end
