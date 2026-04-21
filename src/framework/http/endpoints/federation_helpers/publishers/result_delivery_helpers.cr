module ACD
  module Kemal
    class App
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
