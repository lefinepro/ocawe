module ACD
  module Kemal
    class App
      private def normalize_federation_activity(raw : String?) : String
        value = raw.to_s.strip.downcase
        return "merge" if value == "merge" || value == "mergerequest"
        "ticket"
      end

      private def federation_actor_from_node(node : JSON::Any?) : String
        return "" unless node
        if hash = node.as_h?
          return pick_first_non_empty(
            hash["id"]?.try(&.as_s?),
            hash["actor"]?.try(&.as_s?),
          )
        end
        node.as_s? || ""
      end

      private def resolve_ticket_workflow_actor(
        body : Hash(String, JSON::Any),
        ticket : Hash(String, JSON::Any),
        local_domain : String
      ) : String
        assignee = ticket["assignee"]?
        attributed_to = ticket["attributedTo"]?
        workflow_actor = pick_first_non_empty(
          federation_actor_from_node(assignee),
          federation_actor_from_node(attributed_to),
          body["workflow_actor"]?.try(&.as_s?),
        )
        return workflow_actor unless workflow_actor.empty?
        workflow_id = pick_first_non_empty(body["workflow_id"]?.try(&.as_s?))
        return "" if workflow_id.empty?
        "#{local_domain}/actors/#{workflow_id}"
      end

      private def process_polled_activity(follow : Hash(String, JSON::Any), activity : Hash(String, JSON::Any)) : Bool
        activity_type = activity["type"]?.try(&.as_s?).to_s
        remote_actor = follow["remote_actor"]?.try(&.as_s?).to_s
        status = follow["status"]?.try(&.as_s?).to_s

        if activity_type == "Accept"
          expected = follow["follow_activity_id"]?.try(&.as_s?).to_s
          object_id = resolve_activity_object_id(activity)
          if !expected.empty? && object_id == expected
            @federation_store.upsert_follow_sync_state(remote_actor: remote_actor, status: "active", error: "")
          end
          return true
        end

        return false unless status == "active"
        ticket_payload = extract_ticket_activity_payload(activity)
        return false unless ticket_payload

        process_ticket_create_activity(
          follow,
          activity,
          ticket_payload[:ticket],
          ticket_payload[:activity_type],
        )
      end

      private def extract_ticket_activity_payload(
        activity : Hash(String, JSON::Any)
      ) : NamedTuple(activity_type: String, ticket: Hash(String, JSON::Any))?
        activity_type = activity["type"]?.try(&.as_s?).to_s.strip

        if activity_type == "Ticket"
          return {
            activity_type: activity_type,
            ticket:        activity,
          }
        end

        return nil unless activity_type == "Create" || activity_type == "Offer"
        ticket = activity["object"]?.try(&.as_h?) || {} of String => JSON::Any
        ticket_type = ticket["type"]?.try(&.as_s?).to_s.strip.downcase
        return nil unless ticket_type == "ticket"

        {
          activity_type: activity_type,
          ticket:        ticket,
        }
      end

      private def ticket_has_offer_attachment?(ticket : Hash(String, JSON::Any)) : Bool
        attachment = ticket["attachment"]?
        if attachment_hash = attachment.try(&.as_h?)
          return attachment_hash["type"]?.try(&.as_s?).to_s.strip.downcase == "offer"
        end
        attachments = attachment.try(&.as_a?) || [] of JSON::Any
        attachments.any? do |entry|
          next false unless entry_hash = entry.as_h?
          entry_hash["type"]?.try(&.as_s?).to_s.strip.downcase == "offer"
        end
      end

      private def activity_reference(value : JSON::Any?) : String
        return "" unless value
        if value_hash = value.as_h?
          return pick_first_non_empty(
            value_hash["id"]?.try(&.as_s?),
            value_hash["context"]?.try(&.as_s?),
            value_hash["url"]?.try(&.as_s?),
          )
        end
        value.as_s? || ""
      end

      private def ticket_offer_attachment_field(ticket : Hash(String, JSON::Any), field : String) : String
        attachment = ticket["attachment"]?
        if attachment_hash = attachment.try(&.as_h?)
          return activity_reference(attachment_hash[field]?)
        end
        attachments = attachment.try(&.as_a?) || [] of JSON::Any
        attachments.each do |entry|
          next unless entry_hash = entry.as_h?
          next unless entry_hash["type"]?.try(&.as_s?).to_s.strip.downcase == "offer"
          return activity_reference(entry_hash[field]?)
        end
        ""
      end

      private def infer_ticket_workflow_activity(
        activity_doc : Hash(String, JSON::Any),
        ticket : Hash(String, JSON::Any),
        incoming_activity_type : String
      ) : String
        explicit = normalize_federation_activity(
          ticket["activity"]?.try(&.as_s?) ||
          activity_doc["activity"]?.try(&.as_s?)
        )
        return explicit unless explicit == "ticket"
        return "merge" if incoming_activity_type == "Offer"
        return "merge" if ticket_has_offer_attachment?(ticket)
        "ticket"
      end

      private def process_ticket_create_activity(
        follow : Hash(String, JSON::Any),
        activity_doc : Hash(String, JSON::Any),
        ticket : Hash(String, JSON::Any),
        incoming_activity_type : String
      ) : Bool
        remote_actor = follow["remote_actor"]?.try(&.as_s?).to_s
        received_at = Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ")
        @federation_store.append_inbox_event(
          actor: remote_actor,
          activity_type: incoming_activity_type,
          payload: activity_doc,
          received_at: received_at,
        )

        local_actor = follow["local_actor"]?.try(&.as_s?).to_s
        local_domain = local_domain_from_actor_url(local_actor)
        workflow_actor = resolve_ticket_workflow_actor(activity_doc, ticket, local_domain)
        if workflow_actor.empty?
          unless remote_actor.empty?
            @federation_store.upsert_follow_sync_state(
              remote_actor: remote_actor,
              status: follow["status"]?.try(&.as_s?) || "active",
              error: "workflow actor is required (assignee/attributedTo/workflow_actor/workflow_id)"
            )
          end
          return false
        end

        workflow_id = workflow_id_from_actor(workflow_actor)
        if workflow_id.empty?
          unless remote_actor.empty?
            @federation_store.upsert_follow_sync_state(
              remote_actor: remote_actor,
              status: follow["status"]?.try(&.as_s?) || "active",
              error: "unable to derive workflow id from actor: #{workflow_actor}"
            )
          end
          return false
        end

        task = ticket["name"]?.try(&.as_s?) || ticket["summary"]?.try(&.as_s?) || ""
        return false if task.strip.empty?
        content = ticket["content"]?.try(&.as_s?) || ""
        activity = infer_ticket_workflow_activity(
          activity_doc,
          ticket,
          incoming_activity_type
        )
        repo_url = pick_first_non_empty(
          ticket["source"]?.try(&.as_s?),
          ticket_offer_attachment_field(ticket, "target"),
          ticket_offer_attachment_field(ticket, "origin"),
          activity_doc["repo_url"]?.try(&.as_s?),
        )
        repo_ref = activity_doc["repo_ref"]?.try(&.as_s?) || "main"
        provider = activity_doc["provider"]?.try(&.as_s?) || "codex"
        ticket_id = ticket["id"]?.try(&.as_s?) || activity_doc["id"]?.try(&.as_s?) || ""

        suffix = Random.rand(UInt64::MAX).to_s(16)
        assign_activity = JSON.parse({
          "@context" => FEDERATION_JSONLD_CONTEXT,
          "id"       => "#{local_domain}/activities/assign-#{suffix}",
          "type"     => "Assign",
          "actor"    => workflow_actor,
          "object"   => JSON.parse(ticket.to_json),
          "target"   => workflow_actor,
        }.to_json).as_h
        @federation_store.append_outbox_event(
          activity: assign_activity,
          event_id: "outbox-assign-#{suffix}",
          published_at: received_at,
        )

        input_data = {
          "input"          => JSON.parse(ticket.to_json),
          "task"           => JSON.parse(task.to_json),
          "content"        => JSON.parse(content.to_json),
          "ticket_id"      => JSON.parse(ticket_id.to_json),
          "ticket"         => JSON.parse(ticket.to_json),
          "repo_url"       => JSON.parse(repo_url.to_json),
          "repo_ref"       => JSON.parse(repo_ref.to_json),
          "provider"       => JSON.parse(provider.to_json),
          "remote_actor"   => JSON.parse(remote_actor.to_json),
          "local_actor"    => JSON.parse(local_actor.to_json),
          "workflow_actor" => JSON.parse(workflow_actor.to_json),
          "api"            => JSON.parse("lefine".to_json),
          "activity"       => JSON.parse(activity.to_json),
        } of String => JSON::Any

        run_result = @workflow_service.start_run(workflow_id, input_data: input_data)
        run_output = run_result.output || {} of String => JSON::Any
        publish_result_activity_from_output(
          workflow_id: workflow_id,
          run_id: run_result.run_id,
          run_status: run_result.status,
          output: run_output,
          ticket: ticket,
          requested_activity: activity,
          remote_actor: remote_actor,
          workflow_actor: workflow_actor,
          local_domain: local_domain,
          published_at: received_at,
        )
        true
      rescue
        false
      end
    end
  end
end
