# Converters for transforming between OpenAI-like APIs and ActivityPub formats
# Based on crater-openai's OpenAINormalizer but adapted for Ocawe framework
# Uses Aptok helpers from the aptok library

require "json"

module Orator
  # Normalized intermediate representation for conversion
  record NormalizedRequest,
    model : String,
    title : String,
    content : String,
    assignee : String?,
    attributed_to : String?,
    metadata : Hash(String, JSON::Any)

  # Converts OpenResponses request to ActivityPub Create{Ticket}
  class OpenResponsesToActivityPub
    def initialize(@actor_url : String? = nil, @local_domain : String? = nil)
    end

    def convert(body : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
      normalized = normalize_from_responses(body)
      build_create_ticket_activity(normalized)
    end

    private def normalize_from_responses(body : Hash(String, JSON::Any)) : NormalizedRequest
      model = body["model"]?.try(&.as_s?).to_s
      raise ArgumentError.new("model is required") if model.empty?

      metadata = body["metadata"]?.try(&.as_h?) || {} of String => JSON::Any
      input = body["input"]?

      text = extract_responses_input(input)
      title = pick_first_non_empty(
        metadata["title"]?.try(&.as_s?),
        text.lines.first?.to_s,
        "OpenResponses request"
      )

      NormalizedRequest.new(
        model: model,
        title: title,
        content: text,
        assignee: metadata["assignee"]?.try(&.as_s?),
        attributed_to: metadata["attributedTo"]?.try(&.as_s?) || metadata["attributed_to"]?.try(&.as_s?),
        metadata: metadata
      )
    end

    private def extract_responses_input(node : JSON::Any?) : String
      return "" unless node
      return node.as_s.to_s.strip if node.as_s?

      if arr = node.as_a?
        return arr.compact_map { |v| extract_response_item(v) }.reject(&.empty?).join("\n")
      end

      if hash = node.as_h?
        return extract_response_item_hash(hash)
      end

      ""
    end

    private def extract_response_item(item : JSON::Any) : String
      hash = item.as_h?
      return item.to_json unless hash

      role = hash["role"]?.try(&.as_s?) || "user"
      if content = hash["content"]?
        if s = content.as_s?
          return "#{role}: #{s}"
        end
        if a = content.as_a?
          txt = a.compact_map do |part|
            part_h = part.as_h?
            next nil unless part_h
            part_h["text"]?.try(&.as_s?) || part_h["content"]?.try(&.as_s?)
          end.join("\n")
          return "#{role}: #{txt}" unless txt.empty?
        end
      end

      item.to_json
    end

    private def extract_response_item_hash(hash : Hash(String, JSON::Any)) : String
      role = hash["role"]?.try(&.as_s?) || "user"
      if content = hash["content"]?
        if s = content.as_s?
          return "#{role}: #{s}"
        end
      end
      hash.to_json
    end

    private def pick_first_non_empty(*values : String?) : String
      values.each do |value|
        next unless value
        stripped = value.strip
        return stripped unless stripped.empty?
      end
      ""
    end

    private def build_create_ticket_activity(req : NormalizedRequest) : Hash(String, JSON::Any)
      # Generate IDs (these will be replaced by actual actor URLs in workflow context)
      actor_url = @actor_url || "temp:actor"
      local_domain = @local_domain || "temp:domain"

      activity_id = "#{local_domain}/activities/create-#{Random::Secure.hex(8)}"
      ticket_id = "#{local_domain}/tickets/#{Random::Secure.hex(8)}"

      # Use Aptok.forgefed_ticket helper to build proper ForgeFed Ticket
      ticket = Aptok.forgefed_ticket(
        ticket_id,
        req.title,
        req.content,
        assignee: req.assignee,
        attributed_to: req.attributed_to || actor_url,
      )

      # Use Aptok.create helper to build proper Create activity
      to = [Aptok::PUBLIC_COLLECTION]
      target = req.metadata["target"]?.try(&.as_s?)

      activity = Aptok.create(activity_id, actor_url, ticket, to, target)

      activity
    end
  end

  # Converts ChatCompletion request to ActivityPub Create{Ticket}
  class ChatCompletionToActivityPub
    def initialize(@actor_url : String? = nil, @local_domain : String? = nil)
    end

    def convert(body : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
      normalized = normalize_from_chat(body)
      build_create_ticket_activity(normalized)
    end

    private def normalize_from_chat(body : Hash(String, JSON::Any)) : NormalizedRequest
      model = body["model"]?.try(&.as_s?).to_s
      raise ArgumentError.new("model is required") if model.empty?

      metadata = body["metadata"]?.try(&.as_h?) || {} of String => JSON::Any
      messages = body["messages"]?.try(&.as_a?) || [] of JSON::Any

      content_lines = [] of String
      first_user = ""
      messages.each do |entry|
        hash = entry.as_h? || next
        role = hash["role"]?.try(&.as_s?).to_s
        text = extract_message_content(hash["content"]?)
        next if text.empty?
        first_user = text if first_user.empty? && role == "user"
        content_lines << "#{role}: #{text}"
      end

      title = pick_first_non_empty(
        metadata["title"]?.try(&.as_s?),
        first_user,
        "ChatCompletion request"
      )

      NormalizedRequest.new(
        model: model,
        title: title,
        content: content_lines.join("\n"),
        assignee: metadata["assignee"]?.try(&.as_s?),
        attributed_to: metadata["attributedTo"]?.try(&.as_s?) || metadata["attributed_to"]?.try(&.as_s?),
        metadata: metadata
      )
    end

    private def extract_message_content(node : JSON::Any?) : String
      return "" unless node
      if raw = node.as_s?
        return raw.strip
      end

      if arr = node.as_a?
        parts = arr.compact_map do |entry|
          hash = entry.as_h?
          next nil unless hash
          hash["text"]?.try(&.as_s?)
        end
        return parts.join("\n").strip
      end

      ""
    end

    private def pick_first_non_empty(*values : String?) : String
      values.each do |value|
        next unless value
        stripped = value.strip
        return stripped unless stripped.empty?
      end
      ""
    end

    private def build_create_ticket_activity(req : NormalizedRequest) : Hash(String, JSON::Any)
      # Generate IDs
      actor_url = @actor_url || "temp:actor"
      local_domain = @local_domain || "temp:domain"

      activity_id = "#{local_domain}/activities/create-#{Random::Secure.hex(8)}"
      ticket_id = "#{local_domain}/tickets/#{Random::Secure.hex(8)}"

      # Use Aptok.forgefed_ticket helper to build proper ForgeFed Ticket
      ticket = Aptok.forgefed_ticket(
        ticket_id,
        req.title,
        req.content,
        assignee: req.assignee,
        attributed_to: req.attributed_to || actor_url,
      )

      # Use Aptok.create helper to build proper Create activity
      to = [Aptok::PUBLIC_COLLECTION]
      target = req.metadata["target"]?.try(&.as_s?)

      activity = Aptok.create(activity_id, actor_url, ticket, to, target)

      activity
    end
  end

  # Converts ActivityPub Create{Note} or Update{Ticket} to OpenResponses response
  class ActivityPubToOpenResponses
    def convert(activity : Hash(String, JSON::Any), original_model : String = "unknown") : Hash(String, JSON::Any)
      activity_type = activity["type"]?.try(&.as_s?).to_s
      obj = activity["object"]?

      case activity_type
      when "Create"
        convert_create_to_responses(activity, obj, original_model)
      when "Update"
        convert_update_to_responses(activity, obj, original_model)
      else
        raise ArgumentError.new("Unsupported activity type: #{activity_type}")
      end
    end

    private def convert_create_to_responses(
      activity : Hash(String, JSON::Any),
      obj : JSON::Any?,
      model : String
    ) : Hash(String, JSON::Any)
      return empty_response(model) unless obj

      obj_hash = obj.as_h?
      return empty_response(model) unless obj_hash

      obj_type = obj_hash["type"]?.try(&.as_s?).to_s
      content = obj_hash["content"]?.try(&.as_s?).to_s

      output_items = [] of Hash(String, JSON::Any)

      unless content.empty?
        output_items << {
          "type" => JSON.parse("text".to_json),
          "text" => JSON.parse(content.to_json),
        } of String => JSON::Any
      end

      build_responses_response(activity, model, output_items)
    end

    private def convert_update_to_responses(
      activity : Hash(String, JSON::Any),
      obj : JSON::Any?,
      model : String
    ) : Hash(String, JSON::Any)
      # Similar to Create, extract content from updated object
      convert_create_to_responses(activity, obj, model)
    end

    private def build_responses_response(
      activity : Hash(String, JSON::Any),
      model : String,
      output_items : Array(Hash(String, JSON::Any))
    ) : Hash(String, JSON::Any)
      activity_id = activity["id"]?.try(&.as_s?).to_s
      published = activity["published"]?.try(&.as_s?).to_s

      created_at = parse_time(published)

      {
        "id" => JSON.parse(activity_id.to_json),
        "object" => JSON.parse("response".to_json),
        "created_at" => JSON.parse(created_at.to_unix.to_json),
        "completed_at" => JSON.parse(Time.utc.to_unix.to_json),
        "status" => JSON.parse("completed".to_json),
        "model" => JSON.parse(model.to_json),
        "output" => JSON.parse(output_items.to_json),
        "usage" => JSON.parse({
          "input_tokens" => 0,
          "output_tokens" => 0,
        }.to_json),
      } of String => JSON::Any
    end

    private def empty_response(model : String) : Hash(String, JSON::Any)
      {
        "id" => JSON.parse("unknown".to_json),
        "object" => JSON.parse("response".to_json),
        "created_at" => JSON.parse(Time.utc.to_unix.to_json),
        "completed_at" => JSON.parse(Time.utc.to_unix.to_json),
        "status" => JSON.parse("completed".to_json),
        "model" => JSON.parse(model.to_json),
        "output" => JSON.parse(([] of Hash(String, JSON::Any)).to_json),
        "usage" => JSON.parse({"input_tokens" => 0, "output_tokens" => 0}.to_json),
      } of String => JSON::Any
    end

    private def parse_time(time_str : String) : Time
      return Time.utc if time_str.empty?
      Time.parse_iso8601(time_str) rescue Time.utc
    end
  end

  # Converts ActivityPub Create{Note} or Update{Ticket} to ChatCompletion response
  class ActivityPubToChatCompletion
    def convert(activity : Hash(String, JSON::Any), original_model : String = "unknown") : Hash(String, JSON::Any)
      obj = activity["object"]?
      obj_hash = obj.try(&.as_h?) || {} of String => JSON::Any

      content = obj_hash["content"]?.try(&.as_s?).to_s
      activity_id = activity["id"]?.try(&.as_s?).to_s
      published = activity["published"]?.try(&.as_s?).to_s

      created = parse_time(published).to_unix

      message = {
        "role" => JSON.parse("assistant".to_json),
        "content" => JSON.parse(content.to_json),
      } of String => JSON::Any

      choice = {
        "index" => JSON.parse("0".to_json),
        "message" => JSON.parse(message.to_json),
        "finish_reason" => JSON.parse("stop".to_json),
      } of String => JSON::Any

      {
        "id" => JSON.parse(activity_id.to_json),
        "object" => JSON.parse("chat.completion".to_json),
        "created" => JSON.parse(created.to_json),
        "model" => JSON.parse(original_model.to_json),
        "choices" => JSON.parse([choice].to_json),
        "usage" => JSON.parse({
          "prompt_tokens" => 0,
          "completion_tokens" => 0,
          "total_tokens" => 0,
        }.to_json),
      } of String => JSON::Any
    end

    private def parse_time(time_str : String) : Time
      return Time.utc if time_str.empty?
      Time.parse_iso8601(time_str) rescue Time.utc
    end
  end
end
