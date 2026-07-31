require "file_utils"
require "http/client"
require "json"
require "aptok"
require "uri"

module Ocawe
  module Pipeline
    extend self

    alias AnyHash = Hash(String, JSON::Any)

    def content_from(activity : AnyHash, object : AnyHash? = nil) : String
      first_string(activity, object, ["prompt", "input", "content", "summary", "name"]) ||
        object.try(&.[]?("source")).try(&.as_h?).try { |source| as_string(source["content"]?) || as_string(source["value"]?) } ||
        ""
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

    def first_attachment_value(activity : AnyHash | JSON::Any, object : AnyHash? | JSON::Any?, names : Enumerable(String)) : String?
      if object
        value = recursive_attachment_value(object, names)
        return value if value && !value.empty?
      end
      recursive_attachment_value(activity, names)
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

    def order_id_from(activity : AnyHash, object : AnyHash? = nil) : String?
      explicit = first_string(activity, object, ["orderId", "fmatch:orderId", "Orator Order ID"])
      return explicit if explicit && !explicit.empty?

      raw = as_string(object.try(&.[]?("id"))) || as_string(activity["id"]?)
      raw.try do |value|
        value.match(/orders\/(\d+)/).try(&.[1]) ||
          value.match(/%2Forders%2F(\d+)/i).try(&.[1]) ||
          value.match(/pipeline-dispatch[^\d]+(\d+)/).try(&.[1]) ||
          value.match(/\/requests\/([^#?]+)/).try(&.[1])
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

    def post_json(url : String, body : String, timeout : Time::Span, headers : HTTP::Headers = default_json_headers) : HTTP::Client::Response
      uri = URI.parse(url)
      HTTP::Client.new(uri) do |client|
        client.compress = false
        client.connect_timeout = timeout
        client.read_timeout = timeout
        client.write_timeout = timeout
        client.post(uri.request_target, headers: headers, body: body)
      end
    end

    def post_json_parse(url : String, body : String, timeout : Time::Span, headers : HTTP::Headers = default_json_headers) : JSON::Any?
      response = post_json(url, body, timeout, headers)
      return nil unless response.status_code.in?(200..299)
      response.body.empty? ? nil : JSON.parse(response.body)
    end

    def post_activity_json(url : String, body : String, timeout : Time::Span) : JSON::Any?
      post_json_parse(
        url,
        body,
        timeout,
        HTTP::Headers{
          "Content-Type" => "application/activity+json",
          "Accept"       => "application/json, application/activity+json",
        }
      )
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

      final_status = status
      final_content = content
      if final_status == "completed" && final_content.strip.empty?
        final_status = "failed"
        final_content = "Model returned an empty response."
      end

      FileUtils.mkdir_p(results_dir)
      body = {
        "order_id"   => order_id,
        "content"    => final_content,
        "model"      => model,
        "endpoint"   => endpoint || "",
        "status"     => final_status,
        "created_at" => Time.utc.to_rfc3339,
      }
      path = File.join(results_dir, "order-#{order_id}.json")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(File.join(results_dir, "order-#{order_id}.json"), body.to_json)
      true
    end

    def wait_order_result(order_id : String, timeout_seconds : Int32, results_dir : String = ENV["OCAWE_RESULTS_DIR"]? || "/results") : Hash(String, String)?
      deadline = Time.monotonic + timeout_seconds.seconds
      path = File.join(results_dir, "order-#{order_id}.json")
      while Time.monotonic < deadline
        if File.exists?(path)
          parsed = JSON.parse(File.read(path))
          return {
            "status"  => string_value(parsed["status"]?),
            "content" => string_value(parsed["content"]?),
            "model"   => string_value(parsed["model"]?),
          }
        end
        sleep 1.seconds
      end
      nil
    end

    def delivery_content(payload : JSON::Any?) : String?
      return nil unless payload
      candidates = [] of JSON::Any
      candidates << payload
      candidates << payload["delivery"] if payload["delivery"]?
      candidates << payload["result"] if payload["result"]?
      if chain = payload["chain"]?.try(&.as_a?)
        chain.each { |item| candidates << item }
      end
      candidates.each do |candidate|
        if text = deep_string(candidate, ["content", "text", "answer", "result"])
          return text unless text.empty?
        end
      end
      nil
    rescue
      nil
    end

    def deep_string(value : JSON::Any, keys : Enumerable(String)) : String?
      wanted = keys.map(&.downcase)
      if hash = value.as_h?
        hash.each do |key, item|
          next unless wanted.includes?(key.downcase)
          found = as_string(item).to_s.strip
          return found unless found.empty?
        end
        hash.each_value do |item|
          if found = deep_string(item, keys)
            return found
          end
        end
      elsif array = value.as_a?
        array.each do |item|
          if found = deep_string(item, keys)
            return found
          end
        end
      end
      nil
    end

    def json_object_from_text(raw : String) : JSON::Any?
      text = raw.strip
      json_start = text.index('{')
      json_end = text.rindex('}')
      return nil unless json_start && json_end && json_end >= json_start
      JSON.parse(text[json_start..json_end])
    rescue
      nil
    end

    def string_array_fields(payload : JSON::Any, keys : Enumerable(String)) : Hash(String, Array(String))
      output = {} of String => Array(String)
      keys.each do |key|
        items = payload[key]?.try(&.as_a?).try do |values|
          values.compact_map { |item| item.as_s?.try(&.strip) }.reject(&.empty?)
        end
        output[key] = items if items && !items.empty?
      end
      output
    end

    def chat_completion_content(base_url : String, key : String, model : String, system : String, user : String, timeout_seconds : Int32 = 60) : String?
      body = {
        "model"       => model.sub(/^chat_completion\//, ""),
        "temperature" => 0,
        "messages"    => [
          {"role" => "system", "content" => system},
          {"role" => "user", "content" => user},
        ],
      }.to_json
      response = post_json(
        "#{base_url.rstrip("/")}/chat/completions",
        body,
        timeout_seconds.seconds,
        HTTP::Headers{
          "Authorization" => "Bearer #{key}",
          "Content-Type"  => "application/json",
          "Accept"        => "application/json",
        }
      )
      return nil unless response.status_code.in?(200..299)
      parsed = JSON.parse(response.body)
      parsed["choices"]?.try(&.as_a?).try(&.first?).try(&.["message"]?).try(&.["content"]?).try(&.as_s?)
    end

    def marketplace_request_activity(
      id : String,
      actor : String,
      target : String,
      title : String,
      content : String,
      resource : String,
      action : String = "deliverService",
      unit : String = "one",
      value : String = "1",
    ) : String
      intent = Aptok.marketplace_intent(
        "#{id}#intent",
        action,
        Aptok.marketplace_quantity(unit, value),
        resource_conforms_to: resource
      )
      proposal = Aptok.marketplace_proposal(
        "#{id}#proposal",
        "request",
        actor,
        intent,
        name: title,
        content: content,
        to: [target]
      )
      Aptok.validate_fep_0837!(proposal)

      activity = Aptok.create(id, actor, proposal)
      activity["to"] = Aptok.json([target])
      activity.to_json
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

    private def recursive_attachment_value(value : AnyHash | JSON::Any, names : Enumerable(String)) : String?
      wanted = names.map(&.downcase)
      hash = value.is_a?(Hash(String, JSON::Any)) ? value : value.as_h?
      return nil unless hash

      if attachments = hash["attachment"]?.try(&.as_a?)
        attachments.each do |entry|
          item = entry.as_h?
          next unless item
          item_name = as_string(item["name"]?) || as_string(item["propertyID"]?)
          next unless wanted.includes?(item_name.to_s.downcase)
          found = as_string(item["value"]?) || as_string(item["href"]?) || as_string(item["content"]?)
          return found if found && !found.empty?
        end
      end

      hash.each_value do |child|
        if found = recursive_attachment_value(child, names)
          return found
        end
      end
      nil
    end
  end
end
