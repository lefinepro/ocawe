module ACD
  module Kemal
    class App
      private def validate_expected_top_level_kind(
        body : Hash(String, JSON::Any),
        contexts : Set(String),
        types : Array(String),
        expected_kind : String
      ) : Array(String)
        errors = [] of String
        type_name = types.first?
        case expected_kind
        when "activity"
          if type_name.nil? || !activity_type_name?(type_name)
            errors << "$.type must be an ActivityStreams or ForgeFed activity for #{context_label(contexts)}"
          else
            errors << "$.actor is required for activity type #{type_name}" if body["actor"]?.nil? && type_name != "IntransitiveActivity"
            unless ACTIVITYSTREAMS_INTRANSITIVE_ACTIVITY_TYPES.includes?(type_name)
              errors << "$.object is required for activity type #{type_name}" if body["object"]?.nil?
            end
          end
        when "actor"
          errors << "$.type must be an actor type for #{context_label(contexts)}" if type_name.nil? || !actor_type_name?(type_name)
        when "collection"
          errors << "$.type must be a Collection or OrderedCollection for #{context_label(contexts)}" if type_name.nil? || !collection_type_name?(type_name)
        end
        errors.concat(validate_known_type_shape(body, "$", types))
        errors
      end

      private def validate_known_type_shape(body : Hash(String, JSON::Any), path : String, types : Array(String)) : Array(String)
        errors = [] of String
        types.each do |type_name|
          if actor_type_name?(type_name)
            errors << "#{path}.inbox is required for actor type #{type_name}" unless has_non_empty_property?(body, "inbox")
            errors << "#{path}.outbox is required for actor type #{type_name}" unless has_non_empty_property?(body, "outbox")
          end
          if collection_type_name?(type_name)
            has_entries = body["orderedItems"]? || body["items"]? || body["first"]?
            errors << "#{path} must expose orderedItems, items, or first for collection type #{type_name}" unless has_entries
          end
          if type_name == "Push"
            errors << "#{path}.target is required for ForgeFed Push" if body["target"]?.nil?
            errors << "#{path}.object is required for ForgeFed Push" if body["object"]?.nil?
          end
          if type_name == "Patch"
            has_patch_payload = body["content"]? || body["url"]?
            errors << "#{path} must include content or url for ForgeFed Patch" unless has_patch_payload
          end
        end
        errors
      end

      private def nested_typed_object_required?(key : String, value : JSON::Any) : Bool
        return false unless value.as_h? || value.as_a?
        %w(actor attributedTo attachment first formerType instrument items next object oneOf anyOf orderedItems origin previous result subject target).includes?(key)
      end

      private def type_allowed_for_contexts?(type_name : String, contexts : Set(String)) : Bool
        return true if contexts.includes?(ACTIVITYSTREAMS_CONTEXT_URL) && ACTIVITYSTREAMS_TYPE_NAMES.includes?(type_name)
        return true if contexts.includes?(FORGEFED_CONTEXT_URL) && FORGEFED_TYPE_NAMES.includes?(type_name)
        false
      end
    end
  end
end
