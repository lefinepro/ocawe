require "aptok"

# ActivityPub federation types for Cawfile workflow input/output validation.
# These types wrap Aptok vocabulary objects and provide validation for
# incoming (Inbox) and outgoing (Outbox) federation activities.
module Api
  module Federation
    # Base module for federation activity validation.
    # Provides common validation logic for ActivityPub/ForgeFed documents.
    module ActivityBase
      # Validates that the document is a valid ActivityPub activity.
      # Returns array of validation errors (empty if valid).
      def self.validate_activity(document : Hash(String, JSON::Any)) : Array(String)
        errors = [] of String

        # Required: type
        type = document["type"]?
        unless type
          errors << "type is required"
          return errors
        end

        type_str = type.as_s? || type.as_a?.try(&.first?.try(&.as_s?))
        unless type_str
          errors << "type must be a string"
          return errors
        end

        # Required: id
        id = document["id"]?
        unless id && id.as_s?
          errors << "id is required and must be a string"
        end

        # Required: actor
        actor = document["actor"]?
        unless actor && (actor.as_s? || actor.as_h?)
          errors << "actor is required"
        end

        errors
      end

      # Validates @context includes ActivityPub context
      def self.validate_context(document : Hash(String, JSON::Any)) : Array(String)
        errors = [] of String
        context = document["@context"]?

        unless context
          errors << "@context is required"
          return errors
        end

        ap_contexts = [
          "https://www.w3.org/ns/activitystreams",
          "https://www.w3.org/ns/activitystreams#",
          "as",
        ]

        has_ap = false
        if ctx_str = context.as_s?
          has_ap = ap_contexts.any? { |c| ctx_str.starts_with?(c) }
        elsif ctx_arr = context.as_a?
          has_ap = ctx_arr.any? do |item|
            if s = item.as_s?
              ap_contexts.any? { |c| s.starts_with?(c) }
            elsif h = item.as_h?
              h.values.any? { |v| v.as_s?.try { |s| ap_contexts.any? { |c| s.starts_with?(c) } } }
            else
              false
            end
          end
        end

        errors << "@context must include ActivityPub namespace" unless has_ap
        errors
      end

      # Full validation: activity + context
      def self.validate(document : Hash(String, JSON::Any)) : Array(String)
        errors = validate_activity(document)
        errors.concat(validate_context(document))

        # If ForgeFed context present, also run ForgeFed validation
        if has_forgefed_context?(document)
          errors.concat(Aptok.forgefed_validation_errors(document))
        end

        errors
      end

      def self.valid?(document : Hash(String, JSON::Any)) : Bool
        validate(document).empty?
      end

      private def self.has_forgefed_context?(document : Hash(String, JSON::Any)) : Bool
        context = document["@context"]?
        return false unless context

        forgefed_url = "https://forgefed.org/ns"

        if ctx_str = context.as_s?
          ctx_str.starts_with?(forgefed_url)
        elsif ctx_arr = context.as_a?
          ctx_arr.any? do |item|
            if s = item.as_s?
              s.starts_with?(forgefed_url)
            elsif h = item.as_h?
              h.values.any? { |v| v.as_s?.try { |s| s.starts_with?(forgefed_url) } }
            else
              false
            end
          end
        else
          false
        end
      end
    end

    # Inbox type for incoming federation activities.
    # Use in Cawfile: `struct Input; include Api::Federation::Inbox; end`
    # Validates incoming ActivityPub activities (Create, Update, Delete, etc.)
    module Inbox
      extend ActivityBase

      # Validates an incoming inbox activity.
      # Checks for required fields and valid ActivityPub structure.
      def self.validate(document : Hash(String, JSON::Any)) : Array(String)
        errors = ActivityBase.validate(document)

        # Inbox-specific: check for supported activity types
        type = document["type"]?
        type_str = type.try(&.as_s?) || type.try(&.as_a?).try(&.first?).try(&.as_s?)

        if type_str
          supported = %w(
            Create Update Delete Follow Accept Reject Add Remove
            Like Announce Undo Block Flag Offer Resolve Apply
            Grant Revoke
          )
          unless supported.includes?(type_str)
            errors << "unsupported inbox activity type: #{type_str}"
          end
        end

        errors
      end
    end

    # Outbox type for outgoing federation activities.
    # Use in Cawfile: `struct Output; include Api::Federation::Outbox; end`
    # Validates outgoing ActivityPub activities with patch support.
    module Outbox
      extend ActivityBase

      # Validates an outgoing outbox activity.
      # Checks for required fields and allows patch-specific types.
      def self.validate(document : Hash(String, JSON::Any)) : Array(String)
        errors = ActivityBase.validate(document)

        # Outbox-specific: check for supported activity types (includes Patch)
        type = document["type"]?
        type_str = type.try(&.as_s?) || type.try(&.as_a?).try(&.first?).try(&.as_s?)

        if type_str
          supported = %w(
            Create Update Delete Follow Accept Reject Add Remove
            Like Announce Undo Block Flag Offer Resolve Apply
            Grant Revoke Push
          )
          unless supported.includes?(type_str)
            errors << "unsupported outbox activity type: #{type_str}"
          end
        end

        # For Push activities (patches), validate additional fields
        if type_str == "Push"
          errors.concat(validate_push_activity(document))
        end

        # For Offer activities (merge requests), validate additional fields
        if type_str == "Offer"
          errors.concat(validate_offer_activity(document))
        end

        errors
      end

      private def self.validate_push_activity(document : Hash(String, JSON::Any)) : Array(String)
        errors = [] of String

        target = document["target"]?
        unless target && (target.as_s? || target.as_h?)
          errors << "Push activity requires target (repository)"
        end

        hash_before = document["hashBefore"]?
        unless hash_before && hash_before.as_s?
          errors << "Push activity requires hashBefore"
        end

        hash_after = document["hashAfter"]?
        unless hash_after && hash_after.as_s?
          errors << "Push activity requires hashAfter"
        end

        object = document["object"]?
        unless object && object.as_h?
          errors << "Push activity requires object (commits collection)"
        end

        errors
      end

      private def self.validate_offer_activity(document : Hash(String, JSON::Any)) : Array(String)
        errors = [] of String

        # Offer for merge requests should have target (branch)
        target = document["target"]?
        unless target && (target.as_s? || target.as_h?)
          errors << "Offer activity for merge request requires target (branch)"
        end

        # Object should be a Ticket or MergeRequest
        obj = document["object"]?
        if obj && obj.as_h?
          obj_type = obj.as_h["type"]?
          obj_type_str = obj_type.try(&.as_s?) || obj_type.try(&.as_a?).try(&.first?).try(&.as_s?)
          if obj_type_str && !obj_type_str.in?("Ticket", "MergeRequest")
            errors << "Offer object must be Ticket or MergeRequest, got: #{obj_type_str}"
          end
        end

        errors
      end
    end
  end
end
