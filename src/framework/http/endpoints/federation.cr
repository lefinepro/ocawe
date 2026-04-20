require "http/headers"
require "base64"
require "uri"

module ACD
  module Kemal
    class App
      FEDERATION_JSONLD_CONTENT_TYPE = "application/ld+json; profile=\"https://www.w3.org/ns/activitystreams\""
      FEDERATION_JSONLD_CONTEXT      = "https://www.w3.org/ns/activitystreams"
      FEDERATION_FORGEFED_CONTEXT    = "https://forgefed.org/ns"

      private def mount_federation_endpoints
        get "/actor/:workflowId" do |env|
          render_local_actor(env, env.params.url["workflowId"]?.to_s)
        end

        get "/actors/:workflow_id" do |env|
          render_local_actor(env, env.params.url["workflow_id"]?.to_s)
        end

        post "/federation/inbox" do |env|
          body = json_body(env)
          next invalid_jsonld(env) unless valid_jsonld_request?(env, body)
          next federation_error(env, 401, "unauthorized", "missing or invalid HTTP Signature") unless valid_http_signature?(env, body)
          if error = validate_contextual_federation_object(body, expected_kind: "activity")
            next federation_error(env, 422, "invalid_activitypub_type", error)
          end

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
            "@context"    => FEDERATION_JSONLD_CONTEXT,
            "status"      => "accepted",
            "received_at" => received_at,
          }.to_json
        end

        get "/federation/following" do |env|
          follows = @federation_store.list_following
          env.response.content_type = FEDERATION_JSONLD_CONTENT_TYPE
          {
            "@context"     => FEDERATION_JSONLD_CONTEXT,
            "type"         => "OrderedCollection",
            "totalItems"   => follows.size,
            "items"        => follows,
            "orderedItems" => follows,
          }.to_json
        end

        post "/federation/follows" do |env|
          body = json_body(env)
          remote_actor = first_non_empty(
            body["actor"]?.try(&.as_s?),
            body["remote_actor"]?.try(&.as_s?),
            body["target"]?.try(&.as_s?),
          )
          next federation_error(env, 400, "bad_request", "actor is required") if remote_actor.empty?

          record = Cogni::Federation::Subscriptions.ensure(@settings, @federation_store, remote_actor)
          env.response.status_code = 201
          env.response.content_type = FEDERATION_JSONLD_CONTENT_TYPE
          {
            "@context" => FEDERATION_JSONLD_CONTEXT,
            "status"   => "subscribed",
            "follow"   => record,
          }.to_json
        end

        get "/federation/outbox" do |env|
          events = @federation_store.list_outbox_events
          items = events.map { |entry| entry["activity"]? || JSON.parse("{}") }
          env.response.content_type = FEDERATION_JSONLD_CONTENT_TYPE
          {
            "@context"     => FEDERATION_JSONLD_CONTEXT,
            "type"         => "OrderedCollection",
            "totalItems"   => events.size,
            "items"        => items,
            "orderedItems" => items,
            "outbox"       => events,
          }.to_json
        end

        post "/federation/outbox" do |env|
          body = json_body(env)
          next invalid_jsonld(env) unless valid_jsonld_request?(env, body)
          if error = validate_contextual_federation_object(body, expected_kind: "activity")
            next federation_error(env, 422, "invalid_activitypub_type", error)
          end
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
            "status"   => "queued",
            "event"    => event,
          }.to_json
        end
      end

      private def render_local_actor(env, workflow_id : String) : String
        document = local_actor_document(workflow_id)
        if document.empty?
          env.response.status_code = 404
          env.response.content_type = FEDERATION_JSONLD_CONTENT_TYPE
          return({
            "@context" => FEDERATION_JSONLD_CONTEXT,
            "type"     => "Error",
            "error"    => {"type" => "not_found", "message" => "unknown workflow actor"},
          }.to_json)
        end

        env.response.content_type = FEDERATION_JSONLD_CONTENT_TYPE
        document.to_json
      end

      private def local_actor_document(workflow_id : String) : Hash(String, JSON::Any)
        return {} of String => JSON::Any if workflow_id.strip.empty?
        return {} of String => JSON::Any unless workflow_ids.includes?(workflow_id)

        actor_url = local_actor_url(workflow_id)
        inbox_url = "#{local_domain_from_actor_url(@settings.federation.local_actor)}/federation/inbox"
        outbox_url = "#{local_domain_from_actor_url(@settings.federation.local_actor)}/federation/outbox"
        public_key_id = "#{actor_url}#main-key"
        public_key_pem = local_actor_public_key_pem
        return {} of String => JSON::Any if public_key_pem.empty?

        JSON.parse({
          "@context" => FEDERATION_JSONLD_CONTEXT,
          "id" => actor_url,
          "type" => "Application",
          "preferredUsername" => workflow_id,
          "name" => workflow_id,
          "inbox" => inbox_url,
          "outbox" => outbox_url,
          "publicKey" => {
            "id" => public_key_id,
            "owner" => actor_url,
            "publicKeyPem" => public_key_pem,
          },
        }.to_json).as_h
      end

      private def local_actor_url(workflow_id : String) : String
        base = local_domain_from_actor_url(@settings.federation.local_actor)
        configured = @settings.federation.local_actor
        if configured.includes?("/actor/")
          "#{base}/actor/#{workflow_id}"
        else
          "#{base}/actors/#{workflow_id}"
        end
      end

      private def local_actor_public_key_pem : String
        key_path = @settings.federation.local_private_key_path
        return "" unless File.exists?(key_path)

        output = IO::Memory.new
        errors = IO::Memory.new
        status = Process.run(
          "openssl",
          args: ["rsa", "-in", key_path, "-pubout"],
          output: output,
          error: errors
        )
        return "" unless status.success?

        output.to_s
      rescue
        ""
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
          "type"     => "Error",
          "error"    => {"type" => type, "message" => message},
        }.to_json
      end

      private def first_non_empty(*values : String?) : String
        values.each do |value|
          next unless value
          stripped = value.strip
          return stripped unless stripped.empty?
        end
        ""
      end
    end
  end
end
