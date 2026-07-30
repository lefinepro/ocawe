module ACD
  module Kemal
    class App
      private def process_aptok_inbox_activity(activity : Aptok::JsonMap) : Bool
        return true if process_registered_aptok_inbox_activity(activity)

        remote_actor = activity["actor"]?.try(&.as_s?).to_s
        follow = if remote_actor.empty?
                   Aptok::JsonMap.new
                 else
                   @federation_kv.get("ocawe:federation:follow:#{remote_actor}").try { |raw| JSON.parse(raw).as_h } || Aptok::JsonMap.new
                 end
        process_polled_activity(follow, activity)
      end

      private def process_registered_aptok_inbox_activity(activity : Aptok::JsonMap) : Bool
        return false unless Ocawe::Workflow.function_registry.registered?("ocawe_handle_aptok_inbox_activity")

        workflow_id = activity["workflow_id"]?.try(&.as_s?).to_s
        if workflow_id.empty?
          ids = workflow_ids
          workflow_id = ids.first if ids.size == 1
        end
        workflow_id = "server" if workflow_id.empty?

        input_data = {
          "activity" => JSON.parse(activity.to_json),
          "api"      => JSON.parse("federation".to_json),
        } of String => JSON::Any
        ctx = Ocawe::Workflow::NodeContext.new(
          workflow_id: workflow_id,
          run_id: "aptok-inbox-#{Random::Secure.hex(12)}",
          node_id: "ocawe_handle_aptok_inbox_activity",
          input_data: input_data,
          state: input_data,
        )
        result = Ocawe::Workflow.function_registry.call("ocawe_handle_aptok_inbox_activity", ctx)
        result["handled"]?.try(&.as_bool?) || false
      rescue ex
        STDERR.puts "[ocawecore] registered inbox handler failed: #{ex.message}"
        false
      end

      private def process_polled_activity(follow : Hash(String, JSON::Any), activity : Hash(String, JSON::Any)) : Bool
        activity_type = activity["type"]?.try(&.as_s?).to_s
        remote_actor = follow["remote_actor"]?.try(&.as_s?).to_s
        status = follow["status"]?.try(&.as_s?).to_s
        STDERR.puts "[federation] inbox activity type=#{activity_type} actor=#{remote_actor} follow_status=#{status}"

        if activity_type == "Accept"
          update_aptok_follow_state(remote_actor, status: "active", error: "") unless remote_actor.empty?
          return true
        end

        return false unless status.empty? || status == "active" || status == "following" || status == "pending"
        ticket_payload = extract_ticket_activity_payload(activity)
        STDERR.puts "[federation] inbox activity ignored: no ticket payload type=#{activity_type}" unless ticket_payload
        return false unless ticket_payload

        process_ticket_create_activity(follow, activity, ticket_payload[:ticket], ticket_payload[:activity_type])
      end

      private def normalize_federation_activity(raw : String?) : String
        value = raw.to_s.strip.downcase
        return "merge" if value == "merge" || value == "mergerequest"
        "ticket"
      end

      private def federation_actor_from_node(node : JSON::Any?) : String
        return "" unless node
        if hash = node.as_h?
          return pick_first_non_empty(hash["id"]?.try(&.as_s?), hash["actor"]?.try(&.as_s?))
        end
        node.as_s? || ""
      end

      private def resolve_ticket_workflow_actor(body : Hash(String, JSON::Any), ticket : Hash(String, JSON::Any), local_domain : String, default_actor : String = "") : String
        assignee = ticket["assignee"]?
        attributed_to = ticket["attributedTo"]?
        workflow_actor = pick_first_non_empty(
          federation_actor_from_node(assignee),
          federation_actor_from_node(attributed_to),
          body["workflow_actor"]?.try(&.as_s?)
        )
        return workflow_actor unless workflow_actor.empty?
        workflow_id = pick_first_non_empty(body["workflow_id"]?.try(&.as_s?))
        return default_actor if workflow_id.empty?
        "#{local_domain}/actors/#{workflow_id}"
      end

      private def extract_ticket_activity_payload(activity : Hash(String, JSON::Any)) : NamedTuple(activity_type: String, ticket: Hash(String, JSON::Any))?
        activity_type = activity["type"]?.try(&.as_s?).to_s.strip
        return {activity_type: activity_type, ticket: activity} if activity_type == "Ticket"
        return nil unless activity_type == "Create" || activity_type == "Offer"
        ticket = activity["object"]?.try(&.as_h?) || {} of String => JSON::Any
        return nil unless ticket["type"]?.try(&.as_s?).to_s.strip.downcase == "ticket"
        {activity_type: activity_type, ticket: ticket}
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
          return pick_first_non_empty(value_hash["id"]?.try(&.as_s?), value_hash["context"]?.try(&.as_s?), value_hash["url"]?.try(&.as_s?))
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

      private def infer_ticket_workflow_activity(activity_doc : Hash(String, JSON::Any), ticket : Hash(String, JSON::Any), incoming_activity_type : String) : String
        explicit = normalize_federation_activity(ticket["activity"]?.try(&.as_s?) || activity_doc["activity"]?.try(&.as_s?))
        return explicit unless explicit == "ticket"
        return "merge" if incoming_activity_type == "Offer"
        return "merge" if ticket_has_offer_attachment?(ticket)
        "ticket"
      end

      private def process_ticket_create_activity(follow : Hash(String, JSON::Any), activity_doc : Hash(String, JSON::Any), ticket : Hash(String, JSON::Any), incoming_activity_type : String) : Bool
        remote_actor = follow["remote_actor"]?.try(&.as_s?).to_s
        received_at = Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ")
        local_actor = follow["local_actor"]?.try(&.as_s?).to_s
        local_actor = @settings.federation.local_actor if local_actor.empty?
        local_domain = local_domain_from_actor_url(local_actor)
        workflow_actor = resolve_ticket_workflow_actor(activity_doc, ticket, local_domain, local_actor)
        STDERR.puts "[federation] ticket ignored: empty workflow actor" if workflow_actor.empty?
        return false if workflow_actor.empty?

        workflow_id = workflow_id_from_actor(workflow_actor)
        workflow_id = registered_ticket_workflow_id(workflow_id, local_actor)
        STDERR.puts "[federation] ticket ignored: empty workflow id actor=#{workflow_actor}" if workflow_id.empty?
        return false if workflow_id.empty?

        task = ticket["name"]?.try(&.as_s?) || ticket["summary"]?.try(&.as_s?) || ""
        STDERR.puts "[federation] ticket ignored: empty task ticket=#{ticket["id"]?.try(&.as_s?).to_s}" if task.strip.empty?
        return false if task.strip.empty?
        content = ticket["content"]?.try(&.as_s?) || ""
        activity = infer_ticket_workflow_activity(activity_doc, ticket, incoming_activity_type)
        repo_url = pick_first_non_empty(
          ticket["source"]?.try(&.as_s?),
          ticket_offer_attachment_field(ticket, "target"),
          ticket_offer_attachment_field(ticket, "origin"),
          activity_doc["repo_url"]?.try(&.as_s?)
        )
        repo_ref = activity_doc["repo_ref"]?.try(&.as_s?) || "main"
        provider = activity_doc["provider"]?.try(&.as_s?) || "codex"
        ticket_id = ticket["id"]?.try(&.as_s?) || activity_doc["id"]?.try(&.as_s?) || ""

        suffix = Random.rand(UInt64::MAX).to_s(16)
        assign_activity = JSON.parse({
          "@context" => [Aptok::ACTIVITYSTREAMS_CONTEXT, Aptok::FORGEFED_CONTEXT],
          "id" => "#{local_domain}/activities/assign-#{suffix}",
          "type" => "Assign",
          "actor" => workflow_actor,
          "object" => JSON.parse(ticket.to_json),
          "target" => workflow_actor,
        }.to_json).as_h
        append_aptok_outbox_event(workflow_actor, assign_activity, "outbox-assign-#{suffix}")

        input_data = {
          "input" => JSON.parse(ticket.to_json),
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
          "api" => JSON.parse("federation".to_json),
          "activity" => JSON.parse(activity.to_json),
          "federation_input" => JSON.parse({
            "api" => "federation",
            "requested_activity" => activity,
            "incoming_activity_type" => incoming_activity_type,
            "activity" => activity_doc,
            "ticket" => ticket,
            "task" => task,
            "content" => content,
            "ticket_id" => ticket_id,
            "repo_url" => repo_url,
            "repo_ref" => repo_ref,
            "remote_actor" => remote_actor,
            "local_actor" => local_actor,
            "workflow_actor" => workflow_actor,
          }.to_json),
          "federation_result_context" => JSON.parse({
            "ticket"             => ticket,
            "requested_activity" => activity,
            "remote_actor"       => remote_actor,
            "workflow_actor"     => workflow_actor,
            "local_domain"       => local_domain,
            "published_at"       => received_at,
          }.to_json),
        } of String => JSON::Any

        if @scheduler.enabled?
          @scheduler.enqueue(
            Ocawe::Workflow::Scheduler::Job.new(
              workflow_id: workflow_id,
              run_id: "federation-#{Random::Secure.hex(12)}",
              input_data: input_data,
            )
          )
          return true
        end

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
      rescue ex
        STDERR.puts "[federation] ticket activity processing failed: #{ex.message || ex.class.name}"
        ex.backtrace?.try(&.each { |line| STDERR.puts line })
        false
      end

      private def workflow_id_from_actor(actor : String) : String
        return "" if actor.strip.empty?
        parts = actor.split('/').reject(&.empty?)
        return "" if parts.empty?
        actor_index = -1
        parts.each_with_index { |part, idx| actor_index = idx if part == "actors" }
        if actor_index >= 0 && actor_index + 1 < parts.size
          candidate = parts[actor_index + 1]
          ids = workflow_ids
          return ids.first if ids.size == 1 && !ids.includes?(candidate)
          return candidate
        end
        fallback = parts.last? || ""
        ids = workflow_ids
        return fallback if fallback.empty? || ids.empty? || ids.includes?(fallback)
        return ids.first if ids.size == 1
        fallback
      end

      private def registered_ticket_workflow_id(candidate : String, local_actor : String) : String
        ids = workflow_ids
        return candidate if ids.empty? || ids.includes?(candidate)

        local_candidate = workflow_id_from_actor(local_actor)
        return local_candidate if ids.includes?(local_candidate)

        preferred = ids.find { |id| id != "actor" && id != "server" }
        preferred || ids.first? || candidate
      end

      private def infer_queue_from_actor(remote_actor : String) : String
        tail = remote_actor.split('/').last?.to_s
        tail.empty? ? "order-queue" : tail
      end

      private def pick_first_non_empty(*values : String?) : String
        values.each do |value|
          next unless value
          stripped = value.strip
          return stripped unless stripped.empty?
        end
        ""
      end

    end
  end
end
