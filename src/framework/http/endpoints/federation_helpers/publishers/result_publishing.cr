module ACD
  module Kemal
    class App
      private def publish_result_activity_from_output(
        workflow_id : String,
        run_id : String,
        run_status : String,
        output : Hash(String, JSON::Any),
        ticket : Hash(String, JSON::Any),
        requested_activity : String,
        remote_actor : String,
        local_actor : String,
        workflow_actor : String,
        local_domain : String,
        published_at : String
      ) : Nil
        effective_output = enrich_output_with_embedded_json(output)
        status = pick_first_non_empty(
          effective_output["agent_status"]?.try(&.as_s?),
          effective_output["project_status"]?.try(&.as_s?),
          effective_output["status"]?.try(&.as_s?),
          run_status,
          "failed",
        )
        requested_activity = normalize_federation_activity(
          pick_first_non_empty(
            requested_activity,
            effective_output["activity"]?.try(&.as_s?),
            ticket["activity"]?.try(&.as_s?)
          )
        )
        suffix = Random.rand(UInt64::MAX).to_s(16)
        explicit_activity = extract_federation_result_activity(effective_output)
        delivery_mode = resolve_result_delivery_mode(
          effective_output: effective_output,
          ticket: ticket,
          remote_actor: remote_actor,
        )
        result_actor = pick_first_non_empty(local_actor, workflow_actor)

        activity = if explicit_activity
                     if requested_activity == "merge"
                       merge_error = validate_merge_offer_activity(explicit_activity)
                       if merge_error.nil?
                         normalize_merge_offer_activity(
                           explicit_activity.not_nil!,
                           suffix: suffix,
                           workflow_actor: workflow_actor,
                           local_domain: local_domain,
                         )
                       else
                         build_note_result_activity(
                           suffix: suffix,
                           ticket: ticket,
                           remote_actor: remote_actor,
                           result_actor: result_actor,
                           local_domain: local_domain,
                           workflow_id: workflow_id,
                           run_id: run_id,
                           result_text: "merge output rejected: #{merge_error}",
                         )
                       end
                     else
                       normalize_federation_result_activity(
                         explicit_activity.not_nil!,
                         suffix: suffix,
                         result_actor: result_actor,
                         local_domain: local_domain,
                       )
                     end
                   elsif requested_activity == "merge"
                     merge_offer = extract_merge_offer_activity(effective_output)
                     merge_error = validate_merge_offer_activity(merge_offer)
                     if merge_error.nil?
                       normalize_merge_offer_activity(
                         merge_offer.not_nil!,
                         suffix: suffix,
                         workflow_actor: workflow_actor,
                         local_domain: local_domain,
                       )
                     else
                       build_note_result_activity(
                         suffix: suffix,
                         ticket: ticket,
                         remote_actor: remote_actor,
                         result_actor: result_actor,
                         local_domain: local_domain,
                         workflow_id: workflow_id,
                         run_id: run_id,
                         result_text: "merge output rejected: #{merge_error}",
                       )
                     end
                   else
                     result_text = pick_first_non_empty(
                       effective_output["federation_result_text"]?.try(&.as_s?),
                       effective_output["result"]?.try(&.as_s?),
                       effective_output["result_text"]?.try(&.as_s?),
                       effective_output["message"]?.try(&.as_s?),
                       effective_output["agent_output"]?.try(&.as_s?),
                       effective_output["content"]?.try(&.as_s?),
                     )
                     return if result_text.empty? && status == "ok"
                     resolved_text = result_text.empty? ? "workflow #{workflow_id} finished with status #{status}" : result_text
                     if delivery_mode == "exchange_update"
                       build_exchange_update_result_activity(
                         suffix: suffix,
                         ticket: ticket,
                         result_actor: result_actor,
                         local_domain: local_domain,
                         result_text: resolved_text,
                         status: normalize_exchange_result_status(status),
                       )
                     else
                       build_note_result_activity(
                         suffix: suffix,
                         ticket: ticket,
                         remote_actor: remote_actor,
                         result_actor: result_actor,
                         local_domain: local_domain,
                         workflow_id: workflow_id,
                         run_id: run_id,
                         result_text: resolved_text,
                       )
                     end
                   end
        activity["to"] = JSON.parse([remote_actor].to_json) unless remote_actor.empty? || activity.has_key?("to")

        @federation_store.append_outbox_event(
          activity: JSON.parse(activity.to_json).as_h,
          event_id: "outbox-result-#{suffix}",
          published_at: published_at,
        )
        return if remote_actor.empty?

        follow = @federation_store.list_following.find { |entry| entry["remote_actor"]?.try(&.as_s?) == remote_actor }
        return unless follow

        remote_inbox = pick_first_non_empty(
          follow["remote_shared_inbox"]?.try(&.as_s?),
          follow["remote_inbox"]?.try(&.as_s?),
        )
        return if remote_inbox.empty?

        deliver_activity!(remote_inbox, JSON.parse(activity.to_json).as_h)
      rescue
      end

      private def enrich_output_with_embedded_json(output : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
        merged = output.dup
        ["agent_output", "content", "federation_result_text", "forgefed_offer", "offer"].each do |key|
          raw = merged[key]?.try(&.as_s?)
          next if raw.nil? || raw.empty?
          parsed = JSON.parse(raw).as_h?
          next unless parsed
          parsed.each do |parsed_key, parsed_value|
            merged[parsed_key] = parsed_value unless merged.has_key?(parsed_key)
          end
        rescue
          # Keep original output when embedded payload is not valid JSON.
        end
        merged
      end

      private def extract_federation_result_activity(output : Hash(String, JSON::Any)) : Hash(String, JSON::Any)?
        federation_output = output["federation_output"]?.try(&.as_h?)
        return nil unless federation_output
        activity = federation_output["activity"]?
        return nil unless activity
        parse_federation_activity_candidate(activity)
      end

      private def parse_federation_activity_candidate(candidate : JSON::Any) : Hash(String, JSON::Any)?
        if hash = candidate.as_h?
          return hash if hash["type"]?.try(&.as_s?)
          nested = hash["activity"]?.try(&.as_h?)
          return nested if nested && nested["type"]?.try(&.as_s?)
        end

        raw = candidate.as_s?
        return nil unless raw
        parsed = JSON.parse(raw)
        parse_federation_activity_candidate(parsed)
      rescue
        nil
      end

      private def normalize_federation_result_activity(
        source : Hash(String, JSON::Any),
        suffix : String,
        result_actor : String,
        local_domain : String
      ) : Hash(String, JSON::Any)
        activity = source.dup
        activity["@context"] = source["@context"]? || JSON.parse([FEDERATION_JSONLD_CONTEXT, FEDERATION_FORGEFED_CONTEXT].to_json)
        activity["id"] = source["id"]? || JSON.parse("#{local_domain}/activities/result-#{suffix}".to_json)
        activity["actor"] = source["actor"]? || JSON.parse(result_actor.to_json)
        activity
      end

      private def build_note_result_activity(
        suffix : String,
        ticket : Hash(String, JSON::Any),
        remote_actor : String,
        result_actor : String,
        local_domain : String,
        workflow_id : String,
        run_id : String,
        result_text : String
      ) : Hash(String, JSON::Any)
        note_id = "#{local_domain}/notes/#{workflow_id}-#{run_id}-#{suffix}"
        ticket_id = ticket["id"]?.try(&.as_s?) || ""
        note = {
          "type"      => JSON.parse("Note".to_json),
          "id"        => JSON.parse(note_id.to_json),
          "name"      => JSON.parse("workflow-result".to_json),
          "content"   => JSON.parse(result_text.to_json),
          "inReplyTo" => JSON.parse(ticket_id.to_json),
        } of String => JSON::Any

        {
          "@context" => JSON.parse(FEDERATION_JSONLD_CONTEXT.to_json),
          "id"       => JSON.parse("#{local_domain}/activities/result-#{suffix}".to_json),
          "type"     => JSON.parse("Create".to_json),
          "actor"    => JSON.parse(result_actor.to_json),
          "object"   => JSON.parse(note.to_json),
        } of String => JSON::Any
      end

      private def build_exchange_update_result_activity(
        suffix : String,
        ticket : Hash(String, JSON::Any),
        result_actor : String,
        local_domain : String,
        result_text : String,
        status : String
      ) : Hash(String, JSON::Any)
        external_id = pick_first_non_empty(
          ticket_attachment_value(ticket, "externalId"),
          ticket["inReplyTo"]?.try(&.as_s?),
          ticket["externalId"]?.try(&.as_s?),
          ticket["id"]?.try(&.as_s?),
        )
        order_id = pick_first_non_empty(
          ticket_attachment_value(ticket, "orderId"),
          ticket["orderId"]?.try(&.as_s?),
        )
        title = pick_first_non_empty(
          ticket["name"]?.try(&.as_s?),
          ticket["summary"]?.try(&.as_s?),
          "workflow-result",
        )

        attachment = [] of Hash(String, JSON::Any)
        attachment << property_value_attachment("status", status)
        attachment << property_value_attachment("orderId", order_id) unless order_id.empty?
        attachment << property_value_attachment("externalId", external_id) unless external_id.empty?

        object = {
          "type"    => JSON.parse("Ticket".to_json),
          "id"      => JSON.parse(external_id.to_json),
          "name"    => JSON.parse(title.to_json),
          "content" => JSON.parse(result_text.to_json),
          "status"  => JSON.parse(status.to_json),
          "updated" => JSON.parse(Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ").to_json),
        } of String => JSON::Any
        object["orderId"] = JSON.parse(order_id.to_json) unless order_id.empty?
        object["externalId"] = JSON.parse(external_id.to_json) unless external_id.empty?
        object["attachment"] = JSON.parse(attachment.to_json) unless attachment.empty?

        activity = {
          "@context" => JSON.parse(FEDERATION_JSONLD_CONTEXT.to_json),
          "id"       => JSON.parse("#{local_domain}/activities/result-#{suffix}".to_json),
          "type"     => JSON.parse("Update".to_json),
          "actor"    => JSON.parse(result_actor.to_json),
          "object"   => JSON.parse(object.to_json),
        } of String => JSON::Any
        activity["target"] = JSON.parse(external_id.to_json) unless external_id.empty?
        activity["orderId"] = JSON.parse(order_id.to_json) unless order_id.empty?
        activity
      end

      private def resolve_result_delivery_mode(
        effective_output : Hash(String, JSON::Any),
        ticket : Hash(String, JSON::Any),
        remote_actor : String
      ) : String
        explicit = pick_first_non_empty(
          effective_output["result_delivery"]?.try(&.as_s?),
          effective_output["delivery_mode"]?.try(&.as_s?),
          effective_output["federation_result_mode"]?.try(&.as_s?),
          ticket["result_delivery"]?.try(&.as_s?),
        ).downcase
        return "exchange_update" if {"exchange_update", "update_ticket", "ticket_update", "update"}.includes?(explicit)
        return "note_create" if {"note_create", "note", "create_note"}.includes?(explicit)
        return "exchange_update" if remote_actor.includes?("exchange.") && remote_actor.includes?("/actor/")
        "note_create"
      end

      private def normalize_exchange_result_status(raw : String) : String
        case raw.strip.downcase
        when "ok", "success", "completed", "done"
          "completed"
        when "failed", "error"
          "failed"
        when "processing", "running", "assigned", "pending"
          "processing"
        else
          "completed"
        end
      end

      private def ticket_attachment_value(ticket : Hash(String, JSON::Any), name : String) : String
        attachments = ticket["attachment"]?.try(&.as_a?) || [] of JSON::Any
        attachments.each do |entry|
          record = entry.as_h?
          next unless record
          next unless record["name"]?.try(&.as_s?) == name
          value = record["value"]?.try(&.as_s?)
          return value.not_nil! if value
        end
        ""
      end

      private def property_value_attachment(name : String, value : String) : Hash(String, JSON::Any)
        {
          "type"  => JSON.parse("PropertyValue".to_json),
          "name"  => JSON.parse(name.to_json),
          "value" => JSON.parse(value.to_json),
        } of String => JSON::Any
      end
    end
  end
end
