module ACD
  module Kemal
    class App
      private def effective_contexts(body : Hash(String, JSON::Any), inherited_contexts : Set(String)) : Set(String)
        contexts = inherited_contexts.dup
        extract_context_urls(body["@context"]?).each { |entry| contexts << entry }
        contexts
      end

      private def extract_context_urls(context : JSON::Any?) : Array(String)
        return [] of String unless context
        return [context.as_s.not_nil!] if context.as_s?
        if values = context.as_a?
          return values.flat_map do |entry|
            if text = entry.as_s?
              [text]
            elsif hash = entry.as_h?
              hash.values.compact_map(&.as_s?)
            else
              [] of String
            end
          end
        end
        if hash = context.as_h?
          return hash.values.compact_map(&.as_s?)
        end
        [] of String
      end

      private def type_names_for(body : Hash(String, JSON::Any)) : Array(String)
        type = body["type"]?
        return [] of String unless type
        return [type.as_s.not_nil!] if type.as_s?
        return type.as_a.not_nil!.compact_map(&.as_s?) if type.as_a?
        [] of String
      end

      private def activity_type_name?(type_name : String) : Bool
        ACTIVITYSTREAMS_ACTIVITY_TYPES.includes?(type_name) || type_name == "Push"
      end

      private def actor_type_name?(type_name : String) : Bool
        ACTIVITYSTREAMS_ACTOR_TYPES.includes?(type_name) || FORGEFED_ACTOR_TYPES.includes?(type_name)
      end

      private def collection_type_name?(type_name : String) : Bool
        ACTIVITYSTREAMS_COLLECTION_TYPES.includes?(type_name)
      end

      private def has_non_empty_property?(body : Hash(String, JSON::Any), key : String) : Bool
        value = body[key]?
        return false unless value
        return !value.as_s.not_nil!.strip.empty? if value.as_s?
        true
      end

      private def context_label(contexts : Set(String)) : String
        return "unknown context" if contexts.empty?
        contexts.to_a.sort.join(", ")
      end
    end
  end
end
