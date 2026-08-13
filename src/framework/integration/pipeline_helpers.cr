require "file_utils"
require "http/client"
require "json"
require "uri"
require "aptok"

module Ocawe
  module Pipeline
    extend self

    alias AnyHash = Hash(String, JSON::Any)
    DEFAULT_CHAT_CONTEXT_INTRO = "Internal conversation context for answering only. Do not mention, quote, summarize, or expose this context section unless the user explicitly asks about prior messages."
    DEFAULT_CHAT_CONTEXT_LABEL = "Current user request. Answer this request directly:"

    def content_from(activity : AnyHash, object : AnyHash? = nil) : String
      first_string(activity, object, ["prompt", "input", "content", "summary", "name"]) ||
        object.try(&.[]?("source")).try(&.as_h?).try { |source| as_string(source["content"]?) || as_string(source["value"]?) } ||
        ""
    end

    def chat_context_prompt(
      messages : Array(JSON::Any)?,
      current_user_text : String,
      intro : String = DEFAULT_CHAT_CONTEXT_INTRO,
      label : String = DEFAULT_CHAT_CONTEXT_LABEL,
    ) : String
      return current_user_text unless messages && messages.size > 1

      history = [] of String
      messages[0, messages.size - 1].each do |message|
        role = message["role"]?.try(&.as_s?).to_s.downcase
        next unless {"system", "user", "assistant"}.includes?(role)
        content = text_from_chat_content(message["content"]?).strip
        next if content.empty?
        history << "#{role.capitalize}: #{content}"
      end

      return current_user_text if history.empty?

      String.build do |io|
        io << intro << "\n"
        io << history.join("\n\n")
        io << "\n\n" << label << "\n"
        io << current_user_text
      end
    end

    def marketplace_request_activity(
      id : String,
      actor : String,
      target : String,
      title : String,
      content : String,
      resource_conforms_to : String,
    ) : String
      intent = Aptok.marketplace_intent(
        id: "#{id}#intent",
        action: "deliverService",
        quantity: Aptok.marketplace_quantity(value: "1"),
        resource_conforms_to: resource_conforms_to,
      )
      proposal = Aptok.marketplace_proposal(
        id: "#{id}#proposal",
        purpose: "request",
        attributed_to: actor,
        publishes: intent,
        name: title,
        content: content,
        to: [target],
      )
      proposal["mediaType"] = Aptok.json("text/plain")
      proposal["source"] = Aptok.json({
        "mediaType" => "text/plain",
        "content"   => content,
      })
      marketplace_context = Aptok.marketplace_context.as_a
      marketplace_context.insert(1, Aptok.json("https://w3id.org/fep/0837"))
      Aptok.object("Offer", id, {
        "@context" => Aptok.json(marketplace_context),
        "actor"    => Aptok.json(actor),
        "to"       => Aptok.json([target]),
        "object"   => Aptok.json(proposal),
      }).to_json
    end

    def first_string(activity : AnyHash, object : AnyHash?, names : Enumerable(String)) : String?
      names.each do |name|
        value = as_string(activity[name]?)
        return value if value && !value.empty?

        value = as_string(object.try(&.[]?(name)))
        return value if value && !value.empty?

        value = attachment_value(object, name)
        return value if value && !value.empty?
      end
    end

    def attachment_value(object : AnyHash?, name : String) : String?
      raw = object.try(&.[]?("attachment"))
      items = [] of JSON::Any
      if array = raw.try(&.as_a?)
        items.concat(array)
      elsif raw.try(&.as_h?)
        items << raw.not_nil!
      end

      items.each do |entry|
        item = entry.as_h?
        next unless item
        item_name = as_string(item["name"]?) || as_string(item["propertyID"]?)
        next unless item_name.to_s.downcase == name.downcase
        return as_string(item["value"]?) || as_string(item["href"]?) || as_string(item["content"]?)
      end
    end

    def get(url : String, timeout : Time::Span, headers : HTTP::Headers = default_json_headers) : HTTP::Client::Response
      uri = URI.parse(url)
      HTTP::Client.new(uri) do |client|
        client.compress = false
        client.connect_timeout = timeout
        client.read_timeout = timeout
        client.write_timeout = timeout
        client.get(uri.request_target, headers: headers)
      end
    end

    def get_json(url : String, timeout : Time::Span, headers : HTTP::Headers = default_json_headers) : JSON::Any
      response = get(url, timeout, headers)
      raise "HTTP #{response.status_code}" unless response.status_code.in?(200..299)
      JSON.parse(response.body)
    end

    def write_order_result(
      order_id : String?,
      content : String,
      model : String,
      endpoint : String? = nil,
      status : String = "completed",
      results_dir : String = ENV["OCAWE_RESULTS_DIR"]? || "/results",
    ) : Bool
      return false unless order_id && !order_id.empty?

      FileUtils.mkdir_p(results_dir)
      body = {
        "order_id"   => order_id,
        "content"    => content,
        "model"      => model,
        "endpoint"   => endpoint || "",
        "status"     => status,
        "created_at" => Time.utc.to_rfc3339,
      }
      path = File.join(results_dir, "order-#{order_id}.json")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(File.join(results_dir, "order-#{order_id}.json"), body.to_json)
      true
    end

    def as_string(value : JSON::Any?) : String?
      return nil unless value
      value.as_s? || value.as_i?.try(&.to_s) || value.as_f?.try(&.to_s) || value.as_bool?.try(&.to_s)
    end

    def string_value(value : JSON::Any?) : String
      as_string(value).to_s
    end

    def float_value(value : JSON::Any?) : Float64
      value.try(&.as_f?) || value.try(&.as_i?).try(&.to_f) || as_string(value).to_s.to_f? || 0.0
    end

    def int_value(value : JSON::Any?) : Int32
      value.try(&.as_i?).try(&.to_i32) || value.try(&.as_f?).try(&.to_i32) || as_string(value).to_s.to_i? || 0
    end

    private def default_json_headers : HTTP::Headers
      HTTP::Headers{
        "Accept"          => "application/json",
        "Accept-Encoding" => "identity",
        "User-Agent"      => "ocawe-pipeline/1.0",
      }
    end

    private def text_from_chat_content(content : JSON::Any?) : String
      return "" unless content
      return content.as_s if content.as_s?
      if items = content.as_a?
        return items.compact_map { |item| text_from_chat_content_item(item) }.join("\n")
      end
      ""
    end

    private def text_from_chat_content_item(item : JSON::Any) : String?
      item["text"]?.try(&.as_s?) ||
        item["content"]?.try(&.as_s?) ||
        item["filename"]?.try(&.as_s?) ||
        item["file_id"]?.try(&.as_s?)
    end
  end
end
