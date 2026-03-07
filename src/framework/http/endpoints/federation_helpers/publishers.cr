module ACD
  module Kemal
    class App
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
    end
  end
end
