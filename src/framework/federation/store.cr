require "json"
require "db"
require "sqlite3"

module Cogni
  module Federation
    alias AnyHash = Hash(String, JSON::Any)

    module Store
      abstract class Base
        abstract def upsert_follow(
          local_actor : String,
          remote_actor : String,
          queue : String,
          capabilities : JSON::Any,
          status : String,
          remote_inbox : String? = nil,
          remote_outbox : String? = nil,
          remote_shared_inbox : String? = nil,
          remote_public_key_id : String? = nil,
          remote_public_key_pem : String? = nil,
          follow_activity_id : String? = nil
        ) : AnyHash
        abstract def list_following : Array(AnyHash)
        abstract def upsert_follow_sync_state(
          remote_actor : String,
          status : String? = nil,
          cursor : String? = nil,
          last_polled_at : String? = nil,
          error : String? = nil
        ) : Nil
        abstract def subscribed?(remote_actor : String) : Bool
        abstract def activity_seen?(remote_actor : String, activity_id : String) : Bool
        abstract def mark_activity_seen(remote_actor : String, activity_id : String, seen_at : String) : Nil
        abstract def append_inbox_event(actor : String, activity_type : String, payload : AnyHash, received_at : String) : AnyHash
        abstract def append_outbox_event(activity : AnyHash, event_id : String, published_at : String) : AnyHash
        abstract def list_outbox_events : Array(AnyHash)

        protected def utc_now : String
          Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ")
        end

        protected def parse_json(raw : String) : JSON::Any
          JSON.parse(raw)
        rescue
          json_any(raw)
        end

        protected def json_any(value) : JSON::Any
          JSON.parse(value.to_json)
        end
      end

      class Memory < Base
        def initialize
          @follows = [] of AnyHash
          @inbox_events = [] of AnyHash
          @outbox_events = [] of AnyHash
          @lock = Mutex.new
        end

        def upsert_follow(
          local_actor : String,
          remote_actor : String,
          queue : String,
          capabilities : JSON::Any,
          status : String,
          remote_inbox : String? = nil,
          remote_outbox : String? = nil,
          remote_shared_inbox : String? = nil,
          remote_public_key_id : String? = nil,
          remote_public_key_pem : String? = nil,
          follow_activity_id : String? = nil
        ) : AnyHash
          now = utc_now
          id = "#{local_actor}|#{remote_actor}"
          created_at = now
          @lock.synchronize do
            if existing = @follows.find { |entry| entry["id"]?.try(&.as_s?) == id }
              created_at = existing["created_at"]?.try(&.as_s?) || now
            end
            record = {
              "id" => json_any(id), "status" => json_any(status), "local_actor" => json_any(local_actor), "remote_actor" => json_any(remote_actor),
              "queue" => json_any(queue), "capabilities" => capabilities,
              "remote_inbox" => json_any(remote_inbox.to_s), "remote_outbox" => json_any(remote_outbox.to_s), "remote_shared_inbox" => json_any(remote_shared_inbox.to_s),
              "remote_public_key_id" => json_any(remote_public_key_id.to_s), "remote_public_key_pem" => json_any(remote_public_key_pem.to_s),
              "follow_activity_id" => json_any(follow_activity_id.to_s), "cursor" => json_any(""), "last_polled_at" => json_any(""), "error" => json_any(""),
              "created_at" => json_any(created_at), "updated_at" => json_any(now),
            } of String => JSON::Any
            idx = @follows.index { |entry| entry["id"]?.try(&.as_s?) == id }
            if idx
              @follows[idx] = record
            else
              @follows << record
            end
            record
          end
        end

        def list_following : Array(AnyHash)
          @lock.synchronize { @follows.dup }
        end

        def upsert_follow_sync_state(
          remote_actor : String,
          status : String? = nil,
          cursor : String? = nil,
          last_polled_at : String? = nil,
          error : String? = nil
        ) : Nil
          @lock.synchronize do
            idx = @follows.index { |entry| entry["remote_actor"]?.try(&.as_s?) == remote_actor }
            return unless idx
            existing = @follows[idx]
            record = existing.dup
            record["status"] = json_any(status) if status
            record["cursor"] = json_any(cursor) if cursor
            record["last_polled_at"] = json_any(last_polled_at) if last_polled_at
            record["error"] = json_any(error) if error
            record["updated_at"] = json_any(utc_now)
            @follows[idx] = record
          end
        end

        def subscribed?(remote_actor : String) : Bool
          @lock.synchronize do
            @follows.any? do |entry|
              status = entry["status"]?.try(&.as_s?).to_s
              (status == "active" || status == "pending") && entry["remote_actor"]?.try(&.as_s?) == remote_actor
            end
          end
        end

        def activity_seen?(remote_actor : String, activity_id : String) : Bool
          @lock.synchronize do
            @inbox_events.any? do |entry|
              payload = entry["payload"]?.try(&.as_h?) || {} of String => JSON::Any
              entry["actor"]?.try(&.as_s?) == remote_actor &&
                payload["id"]?.try(&.as_s?) == activity_id
            end
          end
        end

        def mark_activity_seen(remote_actor : String, activity_id : String, seen_at : String) : Nil
          payload = {"id" => json_any(activity_id)} of String => JSON::Any
          append_inbox_event(remote_actor, "seen", payload, seen_at)
        end

        def append_inbox_event(actor : String, activity_type : String, payload : AnyHash, received_at : String) : AnyHash
          record = {
            "actor" => json_any(actor), "activity" => json_any(activity_type), "payload" => JSON.parse(payload.to_json), "received_at" => json_any(received_at),
          } of String => JSON::Any
          @lock.synchronize { @inbox_events << record }
          record
        end

        def append_outbox_event(activity : AnyHash, event_id : String, published_at : String) : AnyHash
          record = {
            "id" => json_any(event_id), "published_at" => json_any(published_at), "activity" => JSON.parse(activity.to_json),
          } of String => JSON::Any
          @lock.synchronize { @outbox_events << record }
          record
        end

        def list_outbox_events : Array(AnyHash)
          @lock.synchronize { @outbox_events.dup }
        end
      end

    end
  end
end

require "./store_sqlite"
