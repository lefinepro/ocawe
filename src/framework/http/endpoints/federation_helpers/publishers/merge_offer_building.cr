module ACD
  module Kemal
    class App
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
          "@context" => JSON.parse([Aptok::ACTIVITYSTREAMS_CONTEXT, Aptok::FORGEFED_CONTEXT].to_json),
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
