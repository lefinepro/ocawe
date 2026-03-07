require "http/headers"
require "base64"

module ACD
  module Kemal
    class App
      FEDERATION_JSONLD_CONTENT_TYPE = "application/ld+json; profile=\"https://www.w3.org/ns/activitystreams\""
      FEDERATION_JSONLD_CONTEXT = "https://www.w3.org/ns/activitystreams"
      FEDERATION_FORGEFED_CONTEXT = "https://forgefed.org/ns"

      private def mount_federation_endpoints
        post "/federation/follows" do |env|
          body = json_body(env)
          next invalid_jsonld(env) unless valid_jsonld_request?(env, body)
          local_actor = resolve_local_actor(body)
          remote_actor = resolve_remote_actor(body)

          if remote_actor.empty?
            next federation_error(env, 400, "bad_request", "Follow requires object/remote_actor")
          end
          local_actor = @settings.federation.local_actor if local_actor.empty?

          queue = body["queue"]?.try(&.as_s?) || infer_queue_from_actor(remote_actor)
          capabilities = body["capabilities"]? || JSON.parse(([] of String).to_json)
          begin
            remote_actor_doc = fetch_jsonld_activity(remote_actor)
          rescue ex
            next federation_error(env, 422, "follow_delivery_error", "failed to fetch remote actor: #{ex.message}")
          end
          remote_inbox = remote_actor_doc["inbox"]?.try(&.as_s?).to_s
          remote_outbox = remote_actor_doc["outbox"]?.try(&.as_s?).to_s
          endpoints = remote_actor_doc["endpoints"]?.try(&.as_h?) || {} of String => JSON::Any
          remote_shared_inbox = endpoints["sharedInbox"]?.try(&.as_s?).to_s
          remote_public_key = remote_actor_doc["publicKey"]?.try(&.as_h?) || {} of String => JSON::Any
          remote_public_key_id = remote_public_key["id"]?.try(&.as_s?).to_s
          remote_public_key_pem = remote_public_key["publicKeyPem"]?.try(&.as_s?).to_s

          if remote_inbox.empty? || remote_outbox.empty?
            next federation_error(env, 400, "bad_request", "remote actor must expose inbox and outbox")
          end

          suffix = Random.rand(UInt64::MAX).to_s(16)
          activity_id = body["id"]?.try(&.as_s?) || "#{local_actor}/follows/#{suffix}"
          follow_activity = JSON.parse({
            "@context" => FEDERATION_JSONLD_CONTEXT,
            "id" => activity_id,
            "type" => "Follow",
            "actor" => local_actor,
            "object" => remote_actor,
          }.to_json).as_h

          delivery_target = remote_shared_inbox.empty? ? remote_inbox : remote_shared_inbox
          begin
            deliver_activity!(delivery_target, follow_activity)
          rescue ex
            next federation_error(env, 422, "follow_delivery_error", "failed to deliver Follow: #{ex.message}")
          end

          record = @federation_store.upsert_follow(
            local_actor: local_actor,
            remote_actor: remote_actor,
            queue: queue,
            capabilities: capabilities,
            status: "pending",
            remote_inbox: remote_inbox,
            remote_outbox: remote_outbox,
            remote_shared_inbox: remote_shared_inbox,
            remote_public_key_id: remote_public_key_id,
            remote_public_key_pem: remote_public_key_pem,
            follow_activity_id: activity_id,
          )

          env.response.status_code = 201
          env.response.content_type = FEDERATION_JSONLD_CONTENT_TYPE
          {
            "@context" => FEDERATION_JSONLD_CONTEXT,
            "status" => "pending",
            "follow" => record,
            "activity" => follow_activity,
          }.to_json
        end

        get "/federation/following" do |env|
          items = @federation_store.list_following
          env.response.content_type = FEDERATION_JSONLD_CONTENT_TYPE
          {
            "@context" => FEDERATION_JSONLD_CONTEXT,
            "type" => "OrderedCollection",
            "totalItems" => items.size,
            "orderedItems" => items.map { |entry| entry["remote_actor"]?.try(&.as_s?) || "" },
            "following" => items,
          }.to_json
        end

        post "/federation/inbox" do |env|
          body = json_body(env)
          next invalid_jsonld(env) unless valid_jsonld_request?(env, body)
          next federation_error(env, 401, "unauthorized", "missing or invalid HTTP Signature") unless valid_http_signature?(env, body)

          activity_type = body["type"]?.try(&.as_s?).to_s.strip
          actor = body["actor"]?.try(&.as_s?) || body["remote_actor"]?.try(&.as_s?) || ""

          if actor.strip.empty?
            next federation_error(env, 400, "bad_request", "actor is required")
          end

          subscribed = @federation_store.subscribed?(actor)

          unless subscribed
            next federation_error(env, 403, "forbidden", "actor is not subscribed")
          end

          received_at = Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ")
          @federation_store.append_inbox_event(
            actor: actor,
            activity_type: activity_type,
            payload: body,
            received_at: received_at,
          )

          if activity_type == "Accept"
            object_id = resolve_activity_object_id(body)
            follows = @federation_store.list_following.select { |entry| entry["remote_actor"]?.try(&.as_s?) == actor }
            follows.each do |follow|
              expected = follow["follow_activity_id"]?.try(&.as_s?).to_s
              next if expected.empty? || object_id != expected
              @federation_store.upsert_follow_sync_state(remote_actor: actor, status: "active", error: "")
            end
          end

          env.response.status_code = 202
          env.response.content_type = FEDERATION_JSONLD_CONTENT_TYPE
          {
            "@context" => FEDERATION_JSONLD_CONTEXT,
            "status" => "accepted",
            "received_at" => received_at,
          }.to_json
        end

        get "/federation/outbox" do |env|
          events = @federation_store.list_outbox_events
          items = events.map { |entry| entry["activity"]? || JSON.parse("{}") }
          env.response.content_type = FEDERATION_JSONLD_CONTENT_TYPE
          {
            "@context" => FEDERATION_JSONLD_CONTEXT,
            "type" => "OrderedCollection",
            "totalItems" => events.size,
            "items" => items,
            "orderedItems" => items,
            "outbox" => events,
          }.to_json
        end

        post "/federation/outbox" do |env|
          body = json_body(env)
          next invalid_jsonld(env) unless valid_jsonld_request?(env, body)
          suffix = Random.rand(UInt64::MAX).to_s(16)
          event = @federation_store.append_outbox_event(
            activity: body,
            event_id: "outbox-#{suffix}",
            published_at: Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ"),
          )

          env.response.status_code = 201
          env.response.content_type = FEDERATION_JSONLD_CONTENT_TYPE
          {
            "@context" => FEDERATION_JSONLD_CONTEXT,
            "status" => "queued",
            "event" => event,
          }.to_json
        end
      end

      private def valid_jsonld_request?(env, body : Hash(String, JSON::Any)) : Bool
        content_type = env.request.headers["Content-Type"]?.to_s.downcase
        has_jsonld_content_type = content_type.includes?("application/ld+json")
        context = body["@context"]?
        has_context = if context_string = context.try(&.as_s?)
                        context_string == FEDERATION_JSONLD_CONTEXT
                      elsif context_array = context.try(&.as_a?)
                        context_array.any? { |entry| entry.as_s? == FEDERATION_JSONLD_CONTEXT }
                      else
                        false
                      end
        has_jsonld_content_type && has_context
      end

      private def invalid_jsonld(env) : String
        federation_error(env, 415, "unsupported_media_type", "federation expects JSON-LD with @context=https://www.w3.org/ns/activitystreams")
      end

      private def federation_error(env, code : Int32, type : String, message : String) : String
        env.response.status_code = code
        env.response.content_type = FEDERATION_JSONLD_CONTENT_TYPE
        {
          "@context" => FEDERATION_JSONLD_CONTEXT,
          "type" => "Error",
          "error" => {"type" => type, "message" => message},
        }.to_json
      end

    end
  end
end
