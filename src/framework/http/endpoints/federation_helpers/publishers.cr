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
        result_text = pick_first_non_empty(
          effective_output["federation_result_text"]?.try(&.as_s?),
          effective_output["agent_output"]?.try(&.as_s?),
          effective_output["content"]?.try(&.as_s?),
        )
        status = pick_first_non_empty(
          effective_output["agent_status"]?.try(&.as_s?),
          effective_output["project_status"]?.try(&.as_s?),
          run_status,
          "failed",
        )
        return if result_text.empty? && status == "ok"

        suffix = Random.rand(UInt64::MAX).to_s(16)
        resolved_text = result_text.empty? ? "workflow #{workflow_id} finished with status #{status}" : result_text
        requested_activity = normalize_federation_activity(
          pick_first_non_empty(
            requested_activity,
            effective_output["activity"]?.try(&.as_s?),
            ticket["activity"]?.try(&.as_s?)
          )
        )
        activity = if requested_activity == "merge"
                     build_merge_result_offer_activity(
                       suffix: suffix,
                       ticket: ticket,
                       output: effective_output,
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

      private def enrich_output_with_embedded_json(output : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
        merged = output.dup
        ["agent_output", "content", "federation_result_text"].each do |key|
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
          "@context" => JSON.parse(FEDERATION_JSONLD_CONTEXT.to_json),
          "id"       => JSON.parse("#{local_domain}/activities/result-#{suffix}".to_json),
          "type"     => JSON.parse("Create".to_json),
          "actor"    => JSON.parse(workflow_actor.to_json),
          "object"   => JSON.parse(note.to_json),
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
        ticket_source_markdown = pick_first_non_empty(
          output["mr_description"]?.try(&.as_s?),
          output["mr_source"]?.try(&.as_s?),
          extract_ticket_source_markdown(ticket),
          result_text,
        )
        repo_url = pick_first_non_empty(
          output["repo_url"]?.try(&.as_s?),
          extract_ticket_offer_field(ticket, "target"),
          extract_ticket_offer_field(ticket, "origin"),
        )
        summary_candidate = pick_first_non_empty(
          output["mr_summary"]?.try(&.as_s?),
          ticket["name"]?.try(&.as_s?),
          ticket["summary"]?.try(&.as_s?),
          "opening-mr",
        )
        mr_summary = html_escape_plain(summary_candidate.gsub(/\s+/, " ").strip)
        mr_summary = "opening-mr" if mr_summary.empty?
        mr_content_html = pick_first_non_empty(
          output["mr_content_html"]?.try(&.as_s?),
          output["mr_html"]?.try(&.as_s?),
          ticket["content"]?.try(&.as_s?),
        )
        if mr_content_html.empty?
          mr_content_html = html_preformatted(ticket_source_markdown)
        end
        mr_diff = output["mr_diff"]?.try(&.as_s?)
        patches = output["mr_patches"]?.try(&.as_a?) || [] of JSON::Any
        patch_media_type = pick_first_non_empty(
          output["mr_patch_media_type"]?.try(&.as_s?),
          "application/x-git-patch",
        )
        origin = pick_first_non_empty(
          output["mr_origin"]?.try(&.as_s?),
          extract_ticket_offer_field(ticket, "origin"),
          repo_url,
        )
        merge_target = pick_first_non_empty(
          output["mr_target"]?.try(&.as_s?),
          extract_ticket_offer_field(ticket, "target"),
          repo_url,
        )
        patch_tracker = pick_first_non_empty(
          output["mr_patch_tracker"]?.try(&.as_s?),
          ticket["target"]?.try(&.as_s?),
          remote_actor,
          merge_target,
        )

        attachment_offer = {
          "type"      => JSON.parse("Offer".to_json),
          "name"      => JSON.parse("opening-mr".to_json),
          "content"   => JSON.parse(result_text.to_json),
          "mediaType" => JSON.parse("text/markdown; variant=Commonmark".to_json),
        } of String => JSON::Any
        attachment_offer["summary"] = JSON.parse(mr_summary.to_json) unless mr_summary.empty?
        attachment_offer["origin"] = JSON.parse(origin.to_json) unless origin.empty?
        attachment_offer["target"] = JSON.parse(merge_target.to_json) unless merge_target.empty?
        patch_collection = build_mr_patch_collection(
          patches,
          mr_diff,
          workflow_actor,
          patch_media_type,
        )
        if patch_collection.nil? && origin.empty?
          patch_collection = JSON.parse({
            "type"         => "OrderedCollection",
            "orderedItems" => [] of String,
            "totalItems"   => 0,
          }.to_json)
        end
        attachment_offer["object"] = patch_collection if patch_collection
        ticket_source = {
          "mediaType" => JSON.parse("text/markdown; variant=Commonmark".to_json),
          "content"   => JSON.parse(ticket_source_markdown.to_json),
        } of String => JSON::Any

        ticket_object = {
          "type"         => JSON.parse("Ticket".to_json),
          "summary"      => JSON.parse(mr_summary.to_json),
          "source"       => JSON.parse(ticket_source.to_json),
          "content"      => JSON.parse(mr_content_html.to_json),
          "mediaType"    => JSON.parse("text/html".to_json),
          "attachment"   => JSON.parse(attachment_offer.to_json),
          "attributedTo" => JSON.parse(workflow_actor.to_json),
        } of String => JSON::Any
        # ForgeFed MR result shape: Offer with object.type=Ticket, no object.id, and attributedTo actor.
        # Spec reference: https://forgefed.org/spec/
        ticket_object["context"] = JSON.parse(patch_tracker.to_json) unless patch_tracker.empty?

        activity = {
          "@context" => JSON.parse(FEDERATION_JSONLD_CONTEXT.to_json),
          "id"       => JSON.parse("#{local_domain}/activities/opening-mr-#{suffix}".to_json),
          "type"     => JSON.parse("Offer".to_json),
          "actor"    => JSON.parse(workflow_actor.to_json),
          "object"   => JSON.parse(ticket_object.to_json),
        } of String => JSON::Any
        activity["target"] = JSON.parse(patch_tracker.to_json) unless patch_tracker.empty?
        activity
      end

      private def extract_ticket_source_markdown(ticket : Hash(String, JSON::Any)) : String
        source = ticket["source"]?
        if source_hash = source.try(&.as_h?)
          return pick_first_non_empty(
            source_hash["content"]?.try(&.as_s?),
            source_hash["id"]?.try(&.as_s?),
          )
        end
        source.try(&.as_s?) || ""
      end

      private def extract_ticket_offer_field(ticket : Hash(String, JSON::Any), field : String) : String
        offer = extract_ticket_offer_attachment(ticket)
        return "" unless offer
        activity_object_reference(offer[field]?)
      end

      private def extract_ticket_offer_attachment(ticket : Hash(String, JSON::Any)) : Hash(String, JSON::Any)?
        attachment = ticket["attachment"]?
        if attachment_hash = attachment.try(&.as_h?)
          return attachment_hash if attachment_hash["type"]?.try(&.as_s?).to_s.strip.downcase == "offer"
          return nil
        end
        attachments = attachment.try(&.as_a?) || [] of JSON::Any
        attachments.each do |entry|
          next unless entry_hash = entry.as_h?
          return entry_hash if entry_hash["type"]?.try(&.as_s?).to_s.strip.downcase == "offer"
        end
        nil
      end

      private def activity_object_reference(value : JSON::Any?) : String
        return "" unless value
        if value_hash = value.as_h?
          return pick_first_non_empty(
            value_hash["id"]?.try(&.as_s?),
            value_hash["context"]?.try(&.as_s?),
            value_hash["url"]?.try(&.as_s?),
            value_hash["href"]?.try(&.as_s?),
          )
        end
        value.as_s? || ""
      end

      private def html_escape_plain(value : String) : String
        value
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .gsub("\"", "&quot;")
          .gsub("'", "&#39;")
      end

      private def html_preformatted(text : String) : String
        escaped = html_escape_plain(text)
        "<pre>#{escaped}</pre>"
      end

      private def build_mr_patch_collection(
        patches : Array(JSON::Any),
        mr_diff : String?,
        workflow_actor : String,
        patch_media_type : String
      ) : JSON::Any?
        items = [] of Hash(String, JSON::Any)

        patches.each_with_index do |entry, idx|
          text = entry.as_s? || entry.to_json
          next if text.strip.empty?
          items << {
            "type"         => JSON.parse("Patch".to_json),
            "id"           => JSON.parse("urn:patch:#{idx + 1}".to_json),
            "name"         => JSON.parse("patch-#{idx + 1}".to_json),
            "attributedTo" => JSON.parse(workflow_actor.to_json),
            "mediaType"    => JSON.parse(patch_media_type.to_json),
            "content"      => JSON.parse(text.to_json),
          } of String => JSON::Any
        end

        if items.empty? && mr_diff
          items << {
            "type"         => JSON.parse("Patch".to_json),
            "id"           => JSON.parse("urn:patch:1".to_json),
            "name"         => JSON.parse("patch-1".to_json),
            "attributedTo" => JSON.parse(workflow_actor.to_json),
            "mediaType"    => JSON.parse(patch_media_type.to_json),
            "content"      => JSON.parse(mr_diff.to_json),
          } of String => JSON::Any
        end

        return nil if items.empty?
        JSON.parse({
          "type"         => "OrderedCollection",
          "totalItems"   => items.size,
          "orderedItems" => items,
        }.to_json)
      end
    end
  end
end
