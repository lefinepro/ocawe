module ACD
  module Kemal
    class App
      ACTIVITYSTREAMS_TYPE_NAMES = Set{
        "Object", "Link", "Activity", "IntransitiveActivity",
        "Accept", "Add", "Announce", "Arrive", "Block", "Create", "Delete", "Dislike",
        "Flag", "Follow", "Ignore", "Invite", "Join", "Leave", "Like", "Listen", "Move",
        "Offer", "Question", "Read", "Reject", "Remove", "TentativeAccept", "TentativeReject",
        "Travel", "Undo", "Update", "View",
        "Actor", "Application", "Group", "Organization", "Person", "Service",
        "Collection", "OrderedCollection", "CollectionPage", "OrderedCollectionPage",
        "Article", "Audio", "Document", "Event", "Image", "Note", "Page",
        "Place", "Profile", "Relationship", "Tombstone", "Video", "Mention",
      }
      ACTIVITYSTREAMS_ACTIVITY_TYPES = Set{
        "Activity", "IntransitiveActivity",
        "Accept", "Add", "Announce", "Arrive", "Block", "Create", "Delete", "Dislike",
        "Flag", "Follow", "Ignore", "Invite", "Join", "Leave", "Like", "Listen", "Move",
        "Offer", "Question", "Read", "Reject", "Remove", "TentativeAccept", "TentativeReject",
        "Travel", "Undo", "Update", "View",
      }
      ACTIVITYSTREAMS_INTRANSITIVE_ACTIVITY_TYPES = Set{"Arrive", "Question", "Travel"}
      ACTIVITYSTREAMS_ACTOR_TYPES                 = Set{"Actor", "Application", "Group", "Organization", "Person", "Service"}
      ACTIVITYSTREAMS_COLLECTION_TYPES            = Set{"Collection", "OrderedCollection", "CollectionPage", "OrderedCollectionPage"}
      FORGEFED_TYPE_NAMES                         = Set{
        "Branch", "Commit", "Factory", "MergeRequest", "Patch", "PatchTracker",
        "Project", "Push", "Repository", "Team", "Ticket", "TicketTracker",
      }
      FORGEFED_ACTOR_TYPES        = Set{"Factory", "PatchTracker", "Project", "Repository", "Team", "TicketTracker"}
      ACTIVITYSTREAMS_CONTEXT_URL = "https://www.w3.org/ns/activitystreams"
      FORGEFED_CONTEXT_URL        = "https://forgefed.org/ns"

      private def validate_contextual_federation_object(body : Hash(String, JSON::Any), expected_kind : String = "object") : String?
        payload = JSON.parse(body.to_json)
        errors = validate_contextual_json_node(
          payload,
          path: "$",
          inherited_contexts: Set(String).new,
          require_type: true,
        )
        if root_hash = payload.as_h?
          root_contexts = effective_contexts(root_hash, Set(String).new)
          root_types = type_names_for(root_hash)
          errors.concat(validate_expected_top_level_kind(root_hash, root_contexts, root_types, expected_kind))
        end
        return nil if errors.empty?
        errors.join(" | ")
      end
    end
  end
end
