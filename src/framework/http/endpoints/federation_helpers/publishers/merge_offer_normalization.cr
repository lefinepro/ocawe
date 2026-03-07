module ACD
  module Kemal
    class App
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
    end
  end
end
