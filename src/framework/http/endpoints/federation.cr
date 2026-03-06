require "http/headers"
require "base64"

module ACD
  module Kemal
    class App
      FEDERATION_JSONLD_CONTENT_TYPE = "application/ld+json; profile=\"https://www.w3.org/ns/activitystreams\""
      FEDERATION_JSONLD_CONTEXT = "https://www.w3.org/ns/activitystreams"

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
          env.response.content_type = FEDERATION_JSONLD_CONTENT_TYPE
          {
            "@context" => FEDERATION_JSONLD_CONTEXT,
            "type" => "OrderedCollection",
            "totalItems" => events.size,
            "orderedItems" => events.map { |entry| entry["activity"]? || JSON.parse("{}") },
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

      private def normalize_federation_activity(raw : String?) : String
        value = raw.to_s.strip.downcase
        return "merge" if value == "merge" || value == "mergerequest"
        "ticket"
      end

      private def federation_actor_from_node(node : JSON::Any?) : String
        return "" unless node
        if hash = node.as_h?
          return pick_first_non_empty(
            hash["id"]?.try(&.as_s?),
            hash["actor"]?.try(&.as_s?),
          )
        end
        node.as_s? || ""
      end

      private def resolve_ticket_workflow_actor(
        body : Hash(String, JSON::Any),
        ticket : Hash(String, JSON::Any),
        local_domain : String
      ) : String
        assignee = ticket["assignee"]?
        attributed_to = ticket["attributedTo"]?
        workflow_actor = pick_first_non_empty(
          federation_actor_from_node(assignee),
          federation_actor_from_node(attributed_to),
          body["workflow_actor"]?.try(&.as_s?),
        )
        return workflow_actor unless workflow_actor.empty?
        "#{local_domain}/actors/prepare-order"
      end

      private def process_polled_activity(follow : Hash(String, JSON::Any), activity : Hash(String, JSON::Any)) : Bool
        activity_type = activity["type"]?.try(&.as_s?).to_s
        remote_actor = follow["remote_actor"]?.try(&.as_s?).to_s
        status = follow["status"]?.try(&.as_s?).to_s

        if activity_type == "Accept"
          expected = follow["follow_activity_id"]?.try(&.as_s?).to_s
          object_id = resolve_activity_object_id(activity)
          if !expected.empty? && object_id == expected
            @federation_store.upsert_follow_sync_state(remote_actor: remote_actor, status: "active", error: "")
          end
          return true
        end

        return false unless activity_type == "Create"
        return false unless status == "active"
        ticket = activity["object"]?.try(&.as_h?) || {} of String => JSON::Any
        ticket_type = ticket["type"]?.try(&.as_s?).to_s.strip.downcase
        return false unless ticket_type == "ticket"

        process_ticket_create_activity(follow, activity, ticket)
      end

      private def process_ticket_create_activity(
        follow : Hash(String, JSON::Any),
        activity_doc : Hash(String, JSON::Any),
        ticket : Hash(String, JSON::Any)
      ) : Bool
        remote_actor = follow["remote_actor"]?.try(&.as_s?).to_s
        received_at = Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ")
        @federation_store.append_inbox_event(
          actor: remote_actor,
          activity_type: "Create",
          payload: activity_doc,
          received_at: received_at,
        )

        local_actor = follow["local_actor"]?.try(&.as_s?).to_s
        local_domain = local_domain_from_actor_url(local_actor)
        workflow_actor = resolve_ticket_workflow_actor(activity_doc, ticket, local_domain)
        workflow_id = workflow_id_from_actor(workflow_actor)
        return false if workflow_id.empty?

        task = ticket["name"]?.try(&.as_s?) || ticket["summary"]?.try(&.as_s?) || ""
        return false if task.strip.empty?
        content = ticket["content"]?.try(&.as_s?) || ""
        activity = normalize_federation_activity(ticket["type"]?.try(&.as_s?) || activity_doc["activity"]?.try(&.as_s?))

        suffix = Random.rand(UInt64::MAX).to_s(16)
        assign_activity = JSON.parse({
          "@context" => FEDERATION_JSONLD_CONTEXT,
          "id" => "#{local_domain}/activities/assign-#{suffix}",
          "type" => "Assign",
          "actor" => workflow_actor,
          "object" => JSON.parse(ticket.to_json),
          "target" => workflow_actor,
        }.to_json).as_h
        @federation_store.append_outbox_event(
          activity: assign_activity,
          event_id: "outbox-assign-#{suffix}",
          published_at: received_at,
        )

        input_data = {
          "task" => JSON.parse(task.to_json),
          "content" => JSON.parse(content.to_json),
          "api" => JSON.parse("lefine".to_json),
          "activity" => JSON.parse(activity.to_json),
        } of String => JSON::Any
        @workflow_service.start_run(workflow_id, input_data: input_data)
        true
      rescue
        false
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

      private def extract_activities_from_outbox(outbox_doc : Hash(String, JSON::Any)) : Array(Hash(String, JSON::Any))
        items = [] of Hash(String, JSON::Any)
        ordered_items = outbox_doc["orderedItems"]?.try(&.as_a?) || [] of JSON::Any
        if ordered_items.empty?
          if first = outbox_doc["first"]?
            first_doc = if first_hash = first.as_h?
                          first_hash
                        elsif first_url = first.as_s?
                          fetch_jsonld_activity(first_url)
                        else
                          {} of String => JSON::Any
                        end
            ordered_items = first_doc["orderedItems"]?.try(&.as_a?) || [] of JSON::Any
          end
        end
        ordered_items.each do |entry|
          hash = entry.as_h?
          items << hash if hash
        end
        items
      end

      private def resolve_activity_object_id(activity : Hash(String, JSON::Any)) : String
        object = activity["object"]?
        if object_string = object.try(&.as_s?)
          return object_string
        end
        object_hash = object.try(&.as_h?) || {} of String => JSON::Any
        object_hash["id"]?.try(&.as_s?).to_s
      end

      private def local_domain_from_request(env) : String
        host = env.request.headers["Host"]?.to_s
        host = "127.0.0.1:4111" if host.nil? || host.empty?
        "http://#{host}"
      end

      private def fetch_jsonld_activity(url : String, follow : Hash(String, JSON::Any)? = nil) : Hash(String, JSON::Any)
        headers = ::HTTP::Headers{
          "Accept" => FEDERATION_JSONLD_CONTENT_TYPE,
        }
        signed = build_signature_headers("get", url, "")
        signed.each { |k, v| headers[k] = v }
        response = ::HTTP::Client.get(url, headers: headers)
        raise "HTTP #{response.status_code} GET #{url}" unless response.status_code >= 200 && response.status_code < 300
        parsed = JSON.parse(response.body).as_h?
        raise "invalid JSON-LD from #{url}" unless parsed
        parsed
      end

      private def deliver_activity!(url : String, activity : Hash(String, JSON::Any)) : Nil
        payload = activity.to_json
        headers = ::HTTP::Headers{
          "Content-Type" => FEDERATION_JSONLD_CONTENT_TYPE,
        }
        signed = build_signature_headers("post", url, payload)
        signed.each { |k, v| headers[k] = v }
        response = ::HTTP::Client.post(url, headers: headers, body: payload)
        raise "HTTP #{response.status_code} POST #{url}" unless response.status_code >= 200 && response.status_code < 300
      end

      private def build_signature_headers(method : String, url : String, _body : String) : Hash(String, String)
        return {} of String => String unless @settings.federation.signatures_required
        uri = URI.parse(url)
        host = uri.host.to_s
        host = "#{host}:#{uri.port}" if uri.port
        path = uri.path.empty? ? "/" : uri.path
        path += "?#{uri.query}" if uri.query
        date = Time.utc.to_s("%a, %d %b %Y %H:%M:%S GMT")
        headers_list = "(request-target) host date"
        signing_string = "(request-target): #{method.downcase} #{path}\nhost: #{host}\ndate: #{date}"
        signature_b64 = sign_string(signing_string)
        signature = %(keyId="#{@settings.federation.local_key_id}",algorithm="rsa-sha256",headers="#{headers_list}",signature="#{signature_b64}")
        {"Date" => date, "Host" => host, "Signature" => signature}
      end

      private def sign_string(data : String) : String
        key_path = @settings.federation.local_private_key_path
        output = IO::Memory.new
        errors = IO::Memory.new
        status = Process.run(
          "openssl",
          args: ["dgst", "-sha256", "-sign", key_path],
          input: IO::Memory.new(data),
          output: output,
          error: errors
        )
        raise "openssl sign failed: #{errors.to_s.strip}" unless status.success?
        Base64.strict_encode(output.to_slice)
      end

      private def valid_http_signature?(env, body : Hash(String, JSON::Any)) : Bool
        return true unless @settings.federation.signatures_required
        signature_header = env.request.headers["Signature"]?.to_s
        return false if signature_header.nil? || signature_header.empty?
        date_header = env.request.headers["Date"]?.to_s
        return false if date_header.nil? || date_header.empty?
        actor = body["actor"]?.try(&.as_s?).to_s
        return false if actor.empty?
        follow = @federation_store.list_following.find { |entry| entry["remote_actor"]?.try(&.as_s?) == actor }
        return false unless follow
        public_key_pem = follow["remote_public_key_pem"]?.try(&.as_s?).to_s
        return false if public_key_pem.empty?
        signature_map = parse_signature_header(signature_header)
        signature_value = signature_map["signature"]?.to_s
        return false if signature_value.empty?
        headers_value = signature_map["headers"]?.to_s
        headers_order = headers_value.empty? ? ["(request-target)"] : headers_value.split(' ')
        signing_lines = [] of String
        headers_order.each do |header_name|
          normalized = header_name.downcase
          value = if normalized == "(request-target)"
                    "#{env.request.method.downcase} #{env.request.path}"
                  elsif normalized == "host"
                    env.request.headers["Host"]?.to_s
                  else
                    env.request.headers[header_name]? || env.request.headers[header_name.capitalize]? || env.request.headers[normalized]?
                  end
          return false if value.nil? || value.to_s.empty?
          signing_lines << "#{normalized}: #{value}"
        end
        signing_string = signing_lines.join("\n")
        signature_data = Base64.decode_string(signature_value)
        verify_signature(signing_string, signature_data, public_key_pem)
      rescue
        false
      end

      private def verify_signature(data : String, signature_data : String, public_key_pem : String) : Bool
        key_path = ""
        data_path = ""
        sig_path = ""
        suffix = Random.rand(UInt64::MAX).to_s(16)
        tmp_dir = ENV["TMPDIR"]? || "/tmp"
        key_path = "#{tmp_dir}/cogni-fed-key-#{suffix}.pem"
        data_path = "#{tmp_dir}/cogni-fed-data-#{suffix}.txt"
        sig_path = "#{tmp_dir}/cogni-fed-signature-#{suffix}.bin"

        File.write(key_path, public_key_pem)
        File.write(data_path, data)
        File.open(sig_path, "wb") { |f| f << signature_data }

        status = Process.run(
          "openssl",
          args: ["dgst", "-sha256", "-verify", key_path, "-signature", sig_path, data_path],
          output: Process::Redirect::Close,
          error: Process::Redirect::Close
        )
        status.success?
      ensure
        if kp = key_path
          File.delete(kp) if !kp.empty? && File.exists?(kp)
        end
        if dp = data_path
          File.delete(dp) if !dp.empty? && File.exists?(dp)
        end
        if sp = sig_path
          File.delete(sp) if !sp.empty? && File.exists?(sp)
        end
      end

      private def parse_signature_header(raw : String) : Hash(String, String)
        values = {} of String => String
        raw.split(",").each do |part|
          kv = part.split("=", 2)
          next if kv.size != 2
          key = kv[0].strip
          value = kv[1].strip
          if value.starts_with?('"') && value.ends_with?('"') && value.size >= 2
            value = value[1, value.size - 2]
          end
          values[key] = value
        end
        values
      end

      private def workflow_id_from_actor(actor : String) : String
        return "" if actor.strip.empty?
        parts = actor.split('/').reject(&.empty?)
        return "" if parts.empty?

        actor_index = -1
        parts.each_with_index do |part, idx|
          actor_index = idx if part == "actors"
        end
        if actor_index >= 0 && actor_index + 1 < parts.size
          return parts[actor_index + 1]
        end
        parts.last? || ""
      end

      private def resolve_local_actor(body : Hash(String, JSON::Any)) : String
        pick_first_non_empty(
          body["actor"]?.try(&.as_s?),
          body["local_actor"]?.try(&.as_s?),
          body["local_actor_id"]?.try(&.as_s?),
        )
      end

      private def resolve_remote_actor(body : Hash(String, JSON::Any)) : String
        object = body["object"]?
        remote_from_object = if object_hash = object.try(&.as_h?)
                               object_hash["id"]?.try(&.as_s?) || object_hash["actor"]?.try(&.as_s?)
                             else
                               object.try(&.as_s?)
                             end
        pick_first_non_empty(
          remote_from_object,
          body["remote_actor"]?.try(&.as_s?),
        )
      end

      private def infer_queue_from_actor(remote_actor : String) : String
        return "order-queue" if remote_actor.empty?
        tail = remote_actor.split('/').last?.to_s
        return "order-queue" if tail.empty?
        tail
      end

      private def pick_first_non_empty(*values : String?) : String
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
