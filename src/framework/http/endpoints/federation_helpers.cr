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
        workflow_id = pick_first_non_empty(
          body["workflow_id"]?.try(&.as_s?),
        )
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

        return false unless activity_type == "Create"
        return false unless status == "active"
        ticket = activity["object"]?.try(&.as_h?) || {} of String => JSON::Any
        ticket_type = ticket["type"]?.try(&.as_s?).to_s.strip.downcase
        return false unless ticket_type == "ticket"

        process_ticket_create_activity(follow, activity, ticket)
      end

      private def process_ticket_create_activity(
        follow : Hash(String, JSON::Any),
        activity_doc : Hash(String, JSON::Any),
        ticket : Hash(String, JSON::Any)
      ) : Bool
        remote_actor = follow["remote_actor"]?.try(&.as_s?).to_s
        received_at = Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ")
        @federation_store.append_inbox_event(
          actor: remote_actor,
          activity_type: "Create",
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
        activity = normalize_federation_activity(
          ticket["activity"]?.try(&.as_s?) ||
          activity_doc["activity"]?.try(&.as_s?)
        )
        repo_url = ticket["source"]?.try(&.as_s?) || activity_doc["repo_url"]?.try(&.as_s?) || ""
        repo_ref = activity_doc["repo_ref"]?.try(&.as_s?) || "main"
        provider = activity_doc["provider"]?.try(&.as_s?) || "codex"
        ticket_id = ticket["id"]?.try(&.as_s?) || activity_doc["id"]?.try(&.as_s?) || ""

        suffix = Random.rand(UInt64::MAX).to_s(16)
        assign_activity = JSON.parse({
          "@context" => FEDERATION_JSONLD_CONTEXT,
          "id" => "#{local_domain}/activities/assign-#{suffix}",
          "type" => "Assign",
          "actor" => workflow_actor,
          "object" => JSON.parse(ticket.to_json),
          "target" => workflow_actor,
        }.to_json).as_h
        @federation_store.append_outbox_event(
          activity: assign_activity,
          event_id: "outbox-assign-#{suffix}",
          published_at: received_at,
        )

        input_data = {
          "task" => JSON.parse(task.to_json),
          "content" => JSON.parse(content.to_json),
          "ticket_id" => JSON.parse(ticket_id.to_json),
          "ticket" => JSON.parse(ticket.to_json),
          "repo_url" => JSON.parse(repo_url.to_json),
          "repo_ref" => JSON.parse(repo_ref.to_json),
          "provider" => JSON.parse(provider.to_json),
          "remote_actor" => JSON.parse(remote_actor.to_json),
          "local_actor" => JSON.parse(local_actor.to_json),
          "workflow_actor" => JSON.parse(workflow_actor.to_json),
          "api" => JSON.parse("lefine".to_json),
          "activity" => JSON.parse(activity.to_json),
        } of String => JSON::Any
        run_result = @workflow_service.start_run(workflow_id, input_data: input_data)
        run_output = run_result.output || {} of String => JSON::Any
        publish_result_activity_from_output(
          workflow_id: workflow_id,
          run_id: run_result.run_id,
          run_status: run_result.status,
          output: run_output,
          ticket: ticket,
          remote_actor: remote_actor,
          workflow_actor: workflow_actor,
          local_domain: local_domain,
          published_at: received_at,
        )
        true
      rescue
        false
      end

      private def publish_result_activity_from_output(
        workflow_id : String,
        run_id : String,
        run_status : String,
        output : Hash(String, JSON::Any),
        ticket : Hash(String, JSON::Any),
        remote_actor : String,
        workflow_actor : String,
        local_domain : String,
        published_at : String
      ) : Nil
        result_text = pick_first_non_empty(
          output["federation_result_text"]?.try(&.as_s?),
          output["agent_output"]?.try(&.as_s?),
          output["content"]?.try(&.as_s?),
        )
        status = pick_first_non_empty(
          output["agent_status"]?.try(&.as_s?),
          output["project_status"]?.try(&.as_s?),
          run_status,
          "failed",
        )
        return if result_text.empty? && status == "ok"

        suffix = Random.rand(UInt64::MAX).to_s(16)
        resolved_text = result_text.empty? ? "workflow #{workflow_id} finished with status #{status}" : result_text
        requested_activity = normalize_federation_activity(output["activity"]?.try(&.as_s?))
        activity = if requested_activity == "merge"
                     build_merge_result_offer_activity(
                       suffix: suffix,
                       ticket: ticket,
                       output: output,
                       remote_actor: remote_actor,
                       workflow_actor: workflow_actor,
                       local_domain: local_domain,
                       result_text: resolved_text,
                     )
                   else
                     build_note_result_activity(
                       suffix: suffix,
                       ticket: ticket,
                       remote_actor: remote_actor,
                       workflow_actor: workflow_actor,
                       local_domain: local_domain,
                       workflow_id: workflow_id,
                       run_id: run_id,
                       result_text: resolved_text,
                     )
                   end
        activity["to"] = JSON.parse([remote_actor].to_json) unless remote_actor.empty?

        @federation_store.append_outbox_event(
          activity: JSON.parse(activity.to_json).as_h,
          event_id: "outbox-result-#{suffix}",
          published_at: published_at,
        )
      rescue
      end

      private def build_note_result_activity(
        suffix : String,
        ticket : Hash(String, JSON::Any),
        remote_actor : String,
        workflow_actor : String,
        local_domain : String,
        workflow_id : String,
        run_id : String,
        result_text : String
      ) : Hash(String, JSON::Any)
        note_id = "#{local_domain}/notes/#{workflow_id}-#{run_id}-#{suffix}"
        ticket_id = ticket["id"]?.try(&.as_s?) || ""
        note = {
          "type" => "Note",
          "id" => note_id,
          "name" => "workflow-result",
          "content" => result_text,
          "inReplyTo" => ticket_id,
        } of String => JSON::Any

        {
          "@context" => FEDERATION_JSONLD_CONTEXT,
          "id" => "#{local_domain}/activities/result-#{suffix}",
          "type" => "Create",
          "actor" => workflow_actor,
          "object" => JSON.parse(note.to_json),
        } of String => JSON::Any
      end

      private def build_merge_result_offer_activity(
        suffix : String,
        ticket : Hash(String, JSON::Any),
        output : Hash(String, JSON::Any),
        remote_actor : String,
        workflow_actor : String,
        local_domain : String,
        result_text : String
      ) : Hash(String, JSON::Any)
        ticket_id = ticket["id"]?.try(&.as_s?) || "#{local_domain}/tickets/#{suffix}"
        repo_url = pick_first_non_empty(
          output["repo_url"]?.try(&.as_s?),
          ticket["source"]?.try(&.as_s?),
        )
        mr_summary = pick_first_non_empty(
          output["mr_summary"]?.try(&.as_s?),
          ticket["name"]?.try(&.as_s?),
          "opening-mr",
        )
        mr_diff = output["mr_diff"]?.try(&.as_s?)
        patches = output["mr_patches"]?.try(&.as_a?) || [] of JSON::Any
        origin = pick_first_non_empty(output["mr_origin"]?.try(&.as_s?), repo_url)
        target = pick_first_non_empty(output["mr_target"]?.try(&.as_s?), repo_url)

        attachment_offer = {
          "type" => JSON.parse("Offer".to_json),
          "name" => JSON.parse("opening-mr".to_json),
          "summary" => JSON.parse(mr_summary.to_json),
          "content" => JSON.parse(result_text.to_json),
          "mediaType" => JSON.parse("text/markdown".to_json),
          "origin" => JSON.parse(origin.to_json),
          "target" => JSON.parse(target.to_json),
          "object" => JSON.parse({
            "type" => "Ticket",
            "name" => mr_summary,
            "content" => result_text,
          }.to_json),
        } of String => JSON::Any
        attachment_offer["patches"] = JSON.parse(patches.to_json) unless patches.empty?
        attachment_offer["mrDiff"] = JSON.parse(mr_diff.to_json) if mr_diff

        ticket_object = {
          "type" => JSON.parse("Ticket".to_json),
          "id" => JSON.parse(ticket_id.to_json),
          "name" => JSON.parse(mr_summary.to_json),
          "content" => JSON.parse(result_text.to_json),
          "source" => JSON.parse(repo_url.to_json),
          "attachment" => JSON.parse([attachment_offer].to_json),
          "attributedTo" => JSON.parse(remote_actor.to_json),
        } of String => JSON::Any

        {
          "@context" => FEDERATION_JSONLD_CONTEXT,
          "id" => "#{local_domain}/activities/opening-mr-#{suffix}",
          "type" => "Offer",
          "actor" => workflow_actor,
          "object" => JSON.parse(ticket_object.to_json),
        } of String => JSON::Any
      end

      private def local_domain_from_actor_url(actor : String) : String
        uri = URI.parse(actor)
        host = uri.host.to_s
        host = "127.0.0.1" if host.empty?
        port = uri.port
        if port
          "#{uri.scheme || "http"}://#{host}:#{port}"
        else
          "#{uri.scheme || "http"}://#{host}"
        end
      rescue
        "http://127.0.0.1:4111"
      end

      private def extract_activities_from_outbox(outbox_doc : Hash(String, JSON::Any)) : Array(Hash(String, JSON::Any))
        items = [] of Hash(String, JSON::Any)
        ordered_items = outbox_doc["orderedItems"]?.try(&.as_a?) || [] of JSON::Any
        if ordered_items.empty?
          if first = outbox_doc["first"]?
            first_doc = if first_hash = first.as_h?
                          first_hash
                        elsif first_url = first.as_s?
                          fetch_jsonld_activity(first_url)
                        else
                          {} of String => JSON::Any
                        end
            ordered_items = first_doc["orderedItems"]?.try(&.as_a?) || [] of JSON::Any
          end
        end
        ordered_items.each do |entry|
          hash = entry.as_h?
          items << hash if hash
        end
        items
      end

      private def resolve_activity_object_id(activity : Hash(String, JSON::Any)) : String
        object = activity["object"]?
        if object_string = object.try(&.as_s?)
          return object_string
        end
        object_hash = object.try(&.as_h?) || {} of String => JSON::Any
        object_hash["id"]?.try(&.as_s?).to_s
      end

      private def local_domain_from_request(env) : String
        host = env.request.headers["Host"]?.to_s
        host = "127.0.0.1:4111" if host.nil? || host.empty?
        "http://#{host}"
      end
    end
  end
end
