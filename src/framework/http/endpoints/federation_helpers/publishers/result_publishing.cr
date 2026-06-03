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
                           workflow_actor: workflow_actor,
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
                         workflow_actor: workflow_actor,
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
                         workflow_actor: workflow_actor,
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
        activity["to"] = JSON.parse([remote_actor].to_json) unless remote_actor.empty? || activity.has_key?("to")

        append_aptok_outbox_event(workflow_actor, JSON.parse(activity.to_json).as_h, "outbox-result-#{suffix}")
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
        workflow_actor : String,
        local_domain : String
      ) : Hash(String, JSON::Any)
        activity = source.dup
        activity["@context"] = source["@context"]? || JSON.parse([Aptok::ACTIVITYSTREAMS_CONTEXT, Aptok::FORGEFED_CONTEXT].to_json)
        activity["id"] = source["id"]? || JSON.parse("#{local_domain}/activities/result-#{suffix}".to_json)
        activity["actor"] = source["actor"]? || JSON.parse(workflow_actor.to_json)
        activity
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
          "type"      => JSON.parse("Note".to_json),
          "id"        => JSON.parse(note_id.to_json),
          "name"      => JSON.parse("workflow-result".to_json),
          "content"   => JSON.parse(result_text.to_json),
          "inReplyTo" => JSON.parse(ticket_id.to_json),
        } of String => JSON::Any

        {
          "@context" => JSON.parse(Aptok::ACTIVITYSTREAMS_CONTEXT.to_json),
          "id"       => JSON.parse("#{local_domain}/activities/result-#{suffix}".to_json),
          "type"     => JSON.parse("Create".to_json),
          "actor"    => JSON.parse(workflow_actor.to_json),
          "object"   => JSON.parse(note.to_json),
        } of String => JSON::Any
      end
    end
  end
end
