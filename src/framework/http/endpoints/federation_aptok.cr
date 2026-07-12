require "aptok"

module ACD
  module Kemal
    class App
      FEDERATION_METADATA_ENV_VAR = "OCAWE_FEDERATION_MD"
      FEP_MARKDOWN_LINK_PATTERN   = /\[([^\]]+)\]\(([^)\s]+)\)/
      FEP_ID_PATTERN              = /[Ff][Ee][Pp]-[0-9a-z]{2,}/
      FEP_FILE_ID_PATTERN         = /fep-([0-9a-z]{2,})\.md$/i

      private record AptokSubscriptionTarget, name : String, remote_actor : String, remote_inbox : String, queue : String

      private def mount_federation_endpoints
        federation = aptok_federation

        get "/actors/:identifier" do |env|
          write_aptok_response(federation, env)
        end
        post "/actors/:identifier/inbox" do |env|
          if response = unsigned_registered_inbox_response(env)
            next response
          end
          write_aptok_response(federation, env)
        end

        get "/actors/:identifier/outbox" do |env|
          write_aptok_response(federation, env)
        end
        get "/actors/:identifier/followers" do |env|
          identifier = env.params.url["identifier"]
          env.response.content_type = "application/activity+json"
          aptok_follow_collection(identifier, "followers").to_json
        end
        get "/actors/:identifier/following" do |env|
          identifier = env.params.url["identifier"]
          env.response.content_type = "application/activity+json"
          aptok_follow_collection(identifier, "following").to_json
        end
        post "/actors/:identifier/outbox" do |env|
          write_aptok_response(federation, env)
        end

        post "/inbox" do |env|
          if response = unsigned_registered_inbox_response(env)
            next response
          end
          write_aptok_response(federation, env)
        end

        get "/.well-known/webfinger" do |env|
          write_aptok_response(federation, env)
        end
        get "/.well-known/nodeinfo" do |env|
          write_aptok_response(federation, env)
        end
        get "/nodeinfo/2.1" do |env|
          write_aptok_response(federation, env)
        end
        get "/federation/metadata" do |env|
          env.response.content_type = "application/json"
          federation_metadata_document.to_json
        end

        get "/FEDERATION.md" do |env|
          metadata_path = federation_markdown_path
          unless File.exists?(metadata_path)
            env.response.status_code = 404
            env.response.content_type = "text/plain"
            next "missing FEDERATION.md"
          end

          env.response.content_type = "text/markdown; charset=utf-8"
          File.read(metadata_path)
        end
      end

      private def write_aptok_response(federation : Aptok::Federation, env) : String
        response = federation.fetch(aptok_request_from_kemal(env), aptok_fetch_options)
        write_aptok_kemal_response(response, env)
        ""
      end

      private def unsigned_registered_inbox_response(env) : String?
        return nil if inbox_signature_verification_required?
        return nil unless Ocawe::Workflow.function_registry.registered?("ocawe_handle_aptok_inbox_activity")

        raw = env.request.body.try(&.gets_to_end).to_s
        activity = JSON.parse(raw).as_h
        if response = activitypub_follow_response(activity)
          env.response.status_code = 202
          env.response.content_type = "application/activity+json"
          return response.to_json
        end
        if activitypub_accept_response(activity)
          env.response.status_code = 202
          env.response.content_type = "application/json"
          return {"handled" => true, "status" => "accepted"}.to_json
        end
        handled = process_registered_aptok_inbox_activity(activity)

        env.response.status_code = handled ? 202 : 204
        env.response.content_type = "application/json"
        {"handled" => handled}.to_json
      rescue ex
        env.response.status_code = 400
        env.response.content_type = "application/json"
        {"error" => {"type" => "bad_request", "message" => ex.message.to_s}}.to_json
      end

      private def aptok_request_from_kemal(env) : Aptok::Request
        query = Hash(String, String).new
        env.request.query_params.each do |key, value|
          query[key] ||= value
        end

        headers = Hash(String, String).new
        env.request.headers.each do |key, values|
          headers[key] = values.join(", ")
        end

        Aptok::Request.new(
          env.request.method,
          env.request.path,
          headers: headers,
          query: query,
          body: env.request.body.try(&.gets_to_end) || ""
        )
      end

      private def write_aptok_kemal_response(response : Aptok::Response, env) : Nil
        env.response.status_code = response.status
        response.headers.each do |key, value|
          env.response.headers[key] = value
        end
        env.response.print response.body
      end

      private def aptok_fetch_options : Aptok::FetchOptions
        Aptok::FetchOptions.new(
          on_not_found: Aptok::RequestHandler.new do |_request|
            Aptok::Response.new(404, {"Content-Type" => "text/plain; charset=utf-8"}, "Not found")
          end,
          on_not_acceptable: Aptok::RequestHandler.new do |_request|
            Aptok::Response.new(
              406,
              {"Content-Type" => Aptok::FEDIFY_TEXT_CONTENT_TYPE, "Vary" => "Accept, Signature"},
              "Not Acceptable"
            )
          end,
          on_unauthorized: Aptok::RequestHandler.new do |_request|
            Aptok::Response.new(403, {"Content-Type" => "text/plain; charset=utf-8"}, "forbidden")
          end
        )
      end

      private def aptok_federation : Aptok::Federation
        if federation = @aptok_federation
          return federation
        end

        queue = Aptok::InProcessMessageQueue.new
        federation = Aptok::Federation.create(
          federation_origin,
          kv: @federation_kv,
          inbox_queue: queue,
          outbox_queue: queue,
          manually_start_queue: true
        )

        federation.actor "/actors/{identifier}" do |ctx, identifier|
          local_workflow_actor_document(ctx, identifier).as(Aptok::JsonMap?)
        end

        federation.key_pairs do |ctx, identifier|
          key = local_actor_key_pair(ctx.get_actor_uri(identifier))
          key ? [key] : [] of Aptok::ActorKeyPair
        end

        federation.signature_keys do |key_id|
          resolve_aptok_signature_key(key_id)
        end

        federation.inbox_signature_verification if inbox_signature_verification_required?

        federation.inbox "/actors/{identifier}/inbox", "/inbox" do |routes|
          routes.with_idempotency(Time::Span.new(hours: 24), "per-inbox")
          routes.on_any do |_ctx, activity|
            process_aptok_inbox_activity(activity)
          end
        end

        federation.outbox "/actors/{identifier}/outbox", ->(_ctx : Aptok::Context, identifier : String) { list_aptok_outbox(identifier) }

        federation.handles do |_ctx, username|
          workflow_ids.includes?(username) || username == configured_local_actor_identifier ? username : nil
        end

        federation.nodeinfo do |_ctx|
          JSON.parse({
            "version" => "2.1",
            "software" => {"name" => "ocawe", "version" => OcaweCore::VERSION},
            "protocols" => ["activitypub"],
            "services" => {"inbound" => [] of String, "outbound" => [] of String},
            "openRegistrations" => false,
            "usage" => {"users" => {"total" => workflow_ids.size}},
            "metadata" => {"forgefed" => true},
          }.to_json).as_h
        end
        @aptok_federation = federation
        federation
      end

      private def inbox_signature_verification_required? : Bool
        override = ENV["OCAWE_FEDERATION_SIGNATURES_REQUIRED"]?
        return false if override && ["false", "0", "no"].includes?(override.strip.downcase)
        @settings.federation.signatures_required
      end

      private def local_domain_from_actor_url(actor : String) : String
        uri = URI.parse(actor)
        host = uri.host.to_s
        host = "127.0.0.1" if host.empty?
        port = uri.port
        if port
          "#{uri.scheme || "http"}://#{host}:#{port}"
        else
          "#{uri.scheme || "http"}://#{host}"
        end
      rescue
        "http://127.0.0.1:4111"
      end

      private def federation_origin : String
        local_domain_from_actor_url(@settings.federation.local_actor)
      end

      private def local_workflow_actor_document(ctx : Aptok::Context, workflow_id : String) : Aptok::JsonMap
        return Aptok::JsonMap.new if workflow_id.strip.empty?
        return Aptok::JsonMap.new unless workflow_ids.includes?(workflow_id) || workflow_id == configured_local_actor_identifier

        actor_uri = ctx.get_actor_uri(workflow_id)
        key = local_actor_key_pair(actor_uri)
        public_key = key ? Aptok.public_key(key) : nil

        Aptok.actor(
          "Application",
          actor_uri,
          workflow_id,
          ctx.get_inbox_uri(workflow_id),
          ctx.get_outbox_uri(workflow_id),
          name: workflow_id,
          shared_inbox: "#{ctx.origin}/inbox",
          public_key: public_key
        )
      end

      private def configured_local_actor_identifier : String
        actor = @settings.federation.local_actor
        tail = actor.split('/').reject(&.empty?).last?.to_s
        tail.empty? ? "server" : tail
      end

      private def local_actor_key_pair(actor_uri : String) : Aptok::ActorKeyPair?
        key_path = @settings.federation.local_private_key_path
        return nil unless File.exists?(key_path)

        public_key = local_actor_public_key_pem(key_path)
        return nil if public_key.empty?

        Aptok::ActorKeyPair.new(
          id: "#{actor_uri}#main-key",
          owner: actor_uri,
          public_key_pem: public_key,
          private_key_path: key_path
        )
      end

      private def local_actor_public_key_pem(key_path : String) : String
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

      private def resolve_aptok_signature_key(key_id : String) : Aptok::ActorKeyPair?
        actor_id = key_id.split('#').first? || ""
        return nil if actor_id.empty?

        actor = aptok_federation.create_context.lookup_object(actor_id)
        public_key = actor.try(&.[]?("publicKey")).try(&.as_h?)
        return nil unless public_key

        owner = public_key["owner"]?.try(&.as_s?) || actor_id
        public_key_pem = public_key["publicKeyPem"]?.try(&.as_s?).to_s
        return nil if public_key_pem.empty?

        Aptok::ActorKeyPair.new(id: key_id, owner: owner, public_key_pem: public_key_pem)
      rescue
        nil
      end

      private def list_aptok_outbox(identifier : String) : Array(Aptok::JsonMap)
        @federation_kv.list("ocawe:federation:outbox:#{identifier}:").compact_map do |entry|
          JSON.parse(entry.value).as_h?
        end
      end

      private def aptok_follow_collection(identifier : String, collection : String) : Hash(String, JSON::Any)
        actor = aptok_federation.create_context.get_actor_uri(identifier)
        prefix = collection == "following" ? "ocawe:federation:follow:" : "ocawe:federation:follower:#{actor}:"
        items = @federation_kv.list(prefix).compact_map do |entry|
          record = JSON.parse(entry.value).as_h?
          next unless record
          if collection == "following"
            next unless record["local_actor"]?.try(&.as_s?) == actor || record["local_actor"]?.try(&.as_s?) == @settings.federation.local_actor
            record["remote_actor"]?.try(&.as_s?)
          else
            record["remote_actor"]?.try(&.as_s?)
          end
        end.reject(&.empty?).uniq
        {
          "@context" => JSON.parse(Aptok::ACTIVITYSTREAMS_CONTEXT.to_json),
          "type" => JSON.parse("OrderedCollection".to_json),
          "id" => JSON.parse("#{actor}/#{collection}".to_json),
          "totalItems" => JSON.parse(items.size.to_json),
          "orderedItems" => JSON.parse(items.to_json),
        }
      end

      private def activitypub_follow_response(activity : Hash(String, JSON::Any)) : Hash(String, JSON::Any)?
        return nil unless activity["type"]?.try(&.as_s?).to_s == "Follow"
        remote_actor = activity["actor"]?.try(&.as_s?).to_s
        local_actor = aptok_activity_reference(activity["object"]?)
        local_actor = @settings.federation.local_actor if local_actor.empty?
        return nil if remote_actor.empty?

        now = Aptok.now
        record = JSON.parse({
          "id" => "#{local_actor}|#{remote_actor}",
          "status" => "active",
          "local_actor" => local_actor,
          "remote_actor" => remote_actor,
          "created_at" => now,
          "updated_at" => now,
        }.to_json).as_h
        @federation_kv.set("ocawe:federation:follower:#{local_actor}:#{remote_actor}", record.to_json)

        accept = JSON.parse({
          "@context" => Aptok::ACTIVITYSTREAMS_CONTEXT,
          "type" => "Accept",
          "id" => "#{local_actor}/activities/accept-#{Random::Secure.hex(12)}",
          "actor" => local_actor,
          "object" => activity,
          "to" => [remote_actor],
          "published" => now,
        }.to_json).as_h
        append_aptok_outbox_event(local_actor, accept, "outbox-accept-#{Random::Secure.hex(12)}")
        accept
      end

      private def activitypub_accept_response(activity : Hash(String, JSON::Any)) : Bool
        return false unless activity["type"]?.try(&.as_s?).to_s == "Accept"
        remote_actor = activity["actor"]?.try(&.as_s?).to_s
        return false if remote_actor.empty?
        update_aptok_follow_state(remote_actor, status: "active", error: "")
        true
      end

      private def aptok_activity_reference(value : JSON::Any?) : String
        return "" unless value
        if hash = value.as_h?
          return hash["id"]?.try(&.as_s?).to_s
        end
        value.as_s? || ""
      end

      private def append_aptok_outbox_event(workflow_actor : String, activity : Hash(String, JSON::Any), event_id : String) : Nil
        workflow_id = workflow_id_from_actor(workflow_actor)
        workflow_id = "server" if workflow_id.empty?
        @federation_kv.set("ocawe:federation:outbox:#{workflow_id}:#{event_id}", activity.to_json)
      end

      private def publish_outbound_federation_output(workflow_id : String, output : Hash(String, JSON::Any)) : Nil
        return unless federation_api_enabled?

        activity = extract_federation_result_activity(output)
        return unless activity

        normalized = normalize_outbound_federation_activity(workflow_id, activity)
        actor = normalized["actor"]?.try(&.as_s?).to_s
        event_id = "outbox-dispatch-#{Random::Secure.hex(12)}"
        append_aptok_outbox_event(actor, normalized, event_id)
        deliver_outbound_federation_activity(normalized)
      rescue ex
        STDERR.puts "[federation] outbound publication failed for #{workflow_id}: #{ex.message || ex.class.name}"
      end

      private def normalize_outbound_federation_activity(workflow_id : String, source : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
        activity = JSON.parse(source.to_json).as_h
        local_actor = @settings.federation.local_actor
        local_actor = "#{federation_origin}/actors/#{workflow_id}" if local_actor.empty?
        actor = activity["actor"]?.try(&.as_s?).to_s
        actor = local_actor if actor.empty?
        activity["@context"] = JSON.parse(Aptok::ACTIVITYSTREAMS_CONTEXT.to_json) unless activity.has_key?("@context")
        activity["actor"] = JSON.parse(actor.to_json)
        activity["id"] = JSON.parse("#{actor}/activities/#{Random::Secure.hex(16)}".to_json) unless activity["id"]?.try(&.as_s?)
        activity
      end

      private def deliver_outbound_federation_activity(activity : Hash(String, JSON::Any)) : Nil
        actor = activity["actor"]?.try(&.as_s?).to_s
        return if actor.empty?

        transport = Aptok::Transport.new
        key_pair = local_actor_key_pair(actor)
        @federation_kv.list("ocawe:federation:follow:").each do |entry|
          follow = JSON.parse(entry.value).as_h
          status = follow["status"]?.try(&.as_s?).to_s
          next unless status.empty? || status == "active"

          inbox = follow["remote_inbox"]?.try(&.as_s?).to_s
          remote_actor = follow["remote_actor"]?.try(&.as_s?).to_s
          next if inbox.empty? || remote_actor.empty?

          deliver_activity_to_inbox(transport, activity, actor, remote_actor, inbox, key_pair)
        rescue ex
          STDERR.puts "[federation] outbound delivery record failed: #{ex.message || ex.class.name}"
        end
      end

      private def deliver_activity_to_inbox(
        transport : Aptok::Transport,
        activity : Hash(String, JSON::Any),
        actor : String,
        remote_actor : String,
        inbox : String,
        key_pair : Aptok::ActorKeyPair?
      ) : Nil
        delivery = Aptok::DeliveryConfig.new(
          inbox: inbox,
          actor: actor,
          target: remote_actor,
          actor_ids: [remote_actor]
        )
        transport.deliver!(delivery, JSON.parse(activity.to_json).as_h, key_pair)
      rescue ex
        STDERR.puts "[federation] outbound delivery failed to #{inbox}: #{ex.message || ex.class.name}"
      end

    end
  end
end
