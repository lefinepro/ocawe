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

        activity = if requested_activity == "merge"
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

        @federation_store.append_outbox_event(
          activity: JSON.parse(activity.to_json).as_h,
          event_id: "outbox-result-#{suffix}",
          published_at: published_at,
        )
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

      private def extract_merge_offer_activity(output : Hash(String, JSON::Any)) : Hash(String, JSON::Any)?
        candidates = [] of JSON::Any
        candidates << JSON.parse(output.to_json)
        [
          output["forgefed_offer"]?,
          output["offer"]?,
          output["agent_output"]?,
          output["content"]?,
          output["federation_result_text"]?,
        ].each { |value| candidates << value if value }

        candidates.each do |candidate|
          offer = parse_offer_candidate(candidate)
          return offer if offer
        end
        nil
      end

      private def parse_offer_candidate(candidate : JSON::Any) : Hash(String, JSON::Any)?
        if hash = candidate.as_h?
          type = hash["type"]?.try(&.as_s?).to_s.strip.downcase
          return hash if type == "offer"
          nested_offer = hash["offer"]?.try(&.as_h?)
          if nested_offer && nested_offer["type"]?.try(&.as_s?).to_s.strip.downcase == "offer"
            return nested_offer
          end
        end

        raw = candidate.as_s?
        return nil unless raw
        parsed = JSON.parse(raw)
        parse_offer_candidate(parsed)
      rescue
        nil
      end

      private def validate_merge_offer_activity(activity : Hash(String, JSON::Any)?) : String?
        return "expected ForgeFed Offer(Ticket) JSON object" unless activity
        return "top-level type must be Offer" unless activity["type"]?.try(&.as_s?).to_s.strip.downcase == "offer"

        ticket = activity["object"]?.try(&.as_h?)
        return "object must be Ticket" unless ticket && ticket["type"]?.try(&.as_s?).to_s.strip.downcase == "ticket"

        offer_attachment = extract_offer_attachment(ticket)
        return "ticket attachment must include Offer object" unless offer_attachment

        patch_collection = offer_attachment.not_nil!["object"]?.try(&.as_h?)
        return "attachment.object must be an OrderedCollection" unless patch_collection && patch_collection["type"]?.try(&.as_s?).to_s.strip.downcase == "orderedcollection"

        patches = patch_collection["orderedItems"]?.try(&.as_a?) || patch_collection["items"]?.try(&.as_a?)
        return "attachment.object must include Patch items" if patches.nil? || patches.empty?

        has_patch_content = patches.any? do |entry|
          patch = entry.as_h?
          next false unless patch
          patch_type = patch["type"]?.try(&.as_s?).to_s.strip.downcase
          patch_content = patch["content"]?.try(&.as_s?).to_s
          patch_type == "patch" && !patch_content.strip.empty?
        end
        return "each merge result must include a Patch with non-empty content" unless has_patch_content

        nil
      end

      private def extract_offer_attachment(ticket : Hash(String, JSON::Any)) : Hash(String, JSON::Any)?
        attachment = ticket["attachment"]?
        if attachment_hash = attachment.try(&.as_h?)
          return attachment_hash if attachment_hash["type"]?.try(&.as_s?).to_s.strip.downcase == "offer"
        elsif attachment_array = attachment.try(&.as_a?)
          attachment_array.each do |entry|
            entry_hash = entry.as_h?
            next unless entry_hash
            return entry_hash if entry_hash["type"]?.try(&.as_s?).to_s.strip.downcase == "offer"
          end
        end
        nil
      end

      private def normalize_merge_offer_activity(
        source : Hash(String, JSON::Any),
        suffix : String,
        workflow_actor : String,
        local_domain : String
      ) : Hash(String, JSON::Any)
        activity = {} of String => JSON::Any
        activity["@context"] = source["@context"]? || JSON.parse([FEDERATION_JSONLD_CONTEXT, FEDERATION_FORGEFED_CONTEXT].to_json)
        activity["id"] = source["id"]? || JSON.parse("#{local_domain}/activities/opening-mr-#{suffix}".to_json)
        activity["type"] = JSON.parse("Offer".to_json)
        activity["actor"] = source["actor"]? || JSON.parse(workflow_actor.to_json)
        copy_allowed_json_field(activity, source, "to")
        copy_allowed_json_field(activity, source, "cc")
        copy_allowed_json_field(activity, source, "target")

        ticket = source["object"]?.try(&.as_h?)
        if ticket
          activity["object"] = JSON.parse(sanitize_merge_offer_ticket(ticket, workflow_actor).to_json)
        end

        activity
      end

      private def copy_allowed_json_field(
        target : Hash(String, JSON::Any),
        source : Hash(String, JSON::Any),
        key : String
      ) : Nil
        value = source[key]?
        return if blank_activity_value?(value)
        target[key] = value.not_nil!
      end

      private def sanitize_merge_offer_ticket(
        source : Hash(String, JSON::Any),
        workflow_actor : String
      ) : Hash(String, JSON::Any)
        ticket = {
          "type" => JSON.parse("Ticket".to_json),
        } of String => JSON::Any
        copy_allowed_json_field(ticket, source, "summary")
        copy_allowed_json_field(ticket, source, "source")
        copy_allowed_json_field(ticket, source, "content")
        copy_allowed_json_field(ticket, source, "mediaType")

        attachment = sanitize_merge_offer_attachment(source["attachment"]?)
        ticket["attachment"] = attachment.not_nil! if attachment

        attributed_to = source["attributedTo"]?
        ticket["attributedTo"] = if blank_activity_value?(attributed_to)
                                   JSON.parse(workflow_actor.to_json)
                                 else
                                   attributed_to.not_nil!
                                 end
        ticket
      end

      private def sanitize_merge_offer_attachment(attachment : JSON::Any?) : JSON::Any?
        offer = extract_offer_attachment_entry(attachment)
        return nil unless offer

        normalized_offer = {
          "type" => JSON.parse("Offer".to_json),
        } of String => JSON::Any
        copy_allowed_json_field(normalized_offer, offer, "name")
        copy_allowed_json_field(normalized_offer, offer, "summary")
        copy_allowed_json_field(normalized_offer, offer, "content")
        copy_allowed_json_field(normalized_offer, offer, "mediaType")
        copy_allowed_json_field(normalized_offer, offer, "origin")
        copy_allowed_json_field(normalized_offer, offer, "target")

        patch_collection = sanitize_merge_offer_patch_collection(offer["object"]?)
        normalized_offer["object"] = patch_collection.not_nil! if patch_collection
        JSON.parse(normalized_offer.to_json)
      end

      private def extract_offer_attachment_entry(attachment : JSON::Any?) : Hash(String, JSON::Any)?
        return nil unless attachment
        if attachment_hash = attachment.as_h?
          return attachment_hash if attachment_hash["type"]?.try(&.as_s?).to_s.strip.downcase == "offer"
          return nil
        end

        attachment_array = attachment.as_a? || [] of JSON::Any
        attachment_array.each do |entry|
          entry_hash = entry.as_h?
          next unless entry_hash
          return entry_hash if entry_hash["type"]?.try(&.as_s?).to_s.strip.downcase == "offer"
        end
        nil
      end

      private def sanitize_merge_offer_patch_collection(collection : JSON::Any?) : JSON::Any?
        collection_hash = collection.try(&.as_h?)
        return nil unless collection_hash

        raw_items = collection_hash["orderedItems"]?.try(&.as_a?) ||
          collection_hash["items"]?.try(&.as_a?) ||
          [] of JSON::Any
        normalized_items = [] of JSON::Any
        raw_items.each do |entry|
          patch_hash = entry.as_h?
          next unless patch_hash
          normalized = sanitize_merge_offer_patch_item(patch_hash)
          next unless normalized
          normalized_items << JSON.parse(normalized.to_json)
        end

        normalized_collection = {
          "type"         => JSON.parse("OrderedCollection".to_json),
          "totalItems"   => JSON.parse(normalized_items.size.to_json),
          "items"        => JSON.parse(normalized_items.to_json),
          "orderedItems" => JSON.parse(normalized_items.to_json),
        } of String => JSON::Any
        JSON.parse(normalized_collection.to_json)
      end

      private def sanitize_merge_offer_patch_item(
        source : Hash(String, JSON::Any)
      ) : Hash(String, JSON::Any)?
        return nil unless source["type"]?.try(&.as_s?).to_s.strip.downcase == "patch"

        patch = {
          "type" => JSON.parse("Patch".to_json),
        } of String => JSON::Any
        copy_allowed_json_field(patch, source, "id")
        copy_allowed_json_field(patch, source, "name")
        copy_allowed_json_field(patch, source, "attributedTo")
        copy_allowed_json_field(patch, source, "mediaType")
        copy_allowed_json_field(patch, source, "content")
        patch
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
        ticket_origin = extract_ticket_offer_attachment_value(ticket, "origin")
        ticket_target = extract_ticket_offer_attachment_value(ticket, "target")
        repo_url = pick_first_non_empty(
          output["repo_url"]?.try(&.as_s?),
          activity_object_reference(ticket_target),
          activity_object_reference(ticket_origin),
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
        mr_diff = nil.as(String?)
        mr_diff_candidate = pick_first_non_empty(
          output["mr_diff"]?.try(&.as_s?),
          output["patch"]?.try(&.as_s?),
          output["diff"]?.try(&.as_s?),
        )
        mr_diff = mr_diff_candidate unless mr_diff_candidate.empty?
        patches = output["mr_patches"]?.try(&.as_a?) ||
          output["patches"]?.try(&.as_a?) ||
          [] of JSON::Any
        if patches.empty?
          if patch_value = output["patch"]?
            if patch_array = patch_value.as_a?
              patches = patch_array
            elsif patch_hash = patch_value.as_h?
              patch_text = pick_first_non_empty(
                patch_hash["content"]?.try(&.as_s?),
                patch_hash["patch"]?.try(&.as_s?),
                patch_hash["diff"]?.try(&.as_s?),
              )
              mr_diff = patch_text if mr_diff.nil? && !patch_text.empty?
            end
          end
        end
        patch_media_type = pick_first_non_empty(
          output["mr_patch_media_type"]?.try(&.as_s?),
          "application/x-git-patch",
        )
        origin_value = output["mr_origin"]? || ticket_origin
        origin_value = JSON.parse(repo_url.to_json) if blank_activity_value?(origin_value) && !repo_url.empty?
        merge_target_value = output["mr_target"]? || ticket_target
        merge_target_value = JSON.parse(repo_url.to_json) if blank_activity_value?(merge_target_value) && !repo_url.empty?
        origin_ref = activity_object_reference(origin_value)
        merge_target_ref = activity_object_reference(merge_target_value)
        patch_tracker = pick_first_non_empty(
          activity_object_reference(output["mr_patch_tracker"]?),
          activity_object_reference(ticket["target"]?),
          remote_actor,
          merge_target_ref,
        )

        attachment_offer = {
          "type"      => JSON.parse("Offer".to_json),
          "name"      => JSON.parse("opening-mr".to_json),
          "content"   => JSON.parse(result_text.to_json),
          "mediaType" => JSON.parse("text/markdown; variant=Commonmark".to_json),
        } of String => JSON::Any
        attachment_offer["summary"] = JSON.parse(mr_summary.to_json) unless mr_summary.empty?
        attachment_offer["origin"] = origin_value.not_nil! unless blank_activity_value?(origin_value)
        attachment_offer["target"] = merge_target_value.not_nil! unless blank_activity_value?(merge_target_value)
        patch_collection = build_mr_patch_collection(
          patches,
          mr_diff,
          workflow_actor,
          patch_media_type,
        )
        if patch_collection.nil? && origin_ref.empty?
          patch_collection = JSON.parse({
            "type"         => "OrderedCollection",
            "items"        => [] of String,
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

        activity = {
          "@context" => JSON.parse([FEDERATION_JSONLD_CONTEXT, FEDERATION_FORGEFED_CONTEXT].to_json),
          "id"       => JSON.parse("#{local_domain}/activities/opening-mr-#{suffix}".to_json),
          "type"     => JSON.parse("Offer".to_json),
          "actor"    => JSON.parse(workflow_actor.to_json),
          "object"   => JSON.parse(ticket_object.to_json),
        } of String => JSON::Any
        activity["to"] = JSON.parse([patch_tracker].to_json) unless patch_tracker.empty?
        cc = build_merge_result_cc(merge_target_ref, patch_tracker)
        activity["cc"] = JSON.parse(cc.to_json) unless cc.empty?
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

      private def extract_ticket_offer_attachment_value(ticket : Hash(String, JSON::Any), field : String) : JSON::Any?
        offer = extract_ticket_offer_attachment(ticket)
        return nil unless offer
        offer[field]?
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

      private def blank_activity_value?(value : JSON::Any?) : Bool
        return true unless value
        if text = value.as_s?
          return text.strip.empty?
        end
        if hash = value.as_h?
          return hash.empty?
        end
        if array = value.as_a?
          return array.empty?
        end
        false
      end

      private def derive_project_reference(ref : String) : String
        return "" if ref.empty?
        if match = ref.match(/^(.*)\/repo(?:\/.*)?$/)
          return match[1]
        end
        if match = ref.match(/^(.*)\/pr-tracker(?:\/.*)?$/)
          return match[1]
        end
        ""
      end

      private def build_merge_result_cc(merge_target : String, patch_tracker : String) : Array(String)
        entries = [] of String
        project = derive_project_reference(merge_target)
        unless project.empty?
          entries << project
          entries << "#{project}/followers"
        end
        unless merge_target.empty?
          entries << merge_target
          entries << "#{merge_target}/followers"
        end
        entries << "#{patch_tracker}/followers" unless patch_tracker.empty?
        entries.uniq
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
          "items"        => items,
          "orderedItems" => items,
        }.to_json)
      end
    end
  end
end
