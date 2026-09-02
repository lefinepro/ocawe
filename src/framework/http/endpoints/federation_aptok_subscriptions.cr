module ACD
  module Kemal
    class App
      private def bootstrap_federation_subscriptions : Nil
        targets = Set(String).new
        @settings.federation.auto_subscribe.each { |entry| targets << entry.strip unless entry.strip.empty? }
        workflow_follow_targets.each { |entry| targets << entry.strip unless entry.strip.empty? }

        targets.each do |entry|
          normalized = entry.strip
          next if normalized.empty?

          begin
            record = ensure_aptok_subscription(normalized)
            STDERR.puts "[federation] subscribed #{normalized} -> #{record["remote_actor"]?.try(&.as_s?) || normalized}"
          rescue ex
            STDERR.puts "[federation] follow subscription failed for #{normalized}: #{ex.message || ex.class.name}"
          end
        end
      end

      private def ensure_aptok_subscription(value : String) : Hash(String, JSON::Any)
        target = parse_aptok_subscription_target(value)
        ctx = aptok_federation.create_context
        actor_doc = begin
          ctx.lookup_object(target.remote_actor, Aptok::LookupObjectOptions.new(cross_origin: "trust"))
        rescue
          nil
        end
        actor_doc ||= Aptok::JsonMap.new
        remote_actor = actor_doc["id"]?.try(&.as_s?) || target.remote_actor
        remote_outbox = subscription_endpoint(
          actor_doc["outbox"]?.try(&.as_s?).to_s,
          target.remote_actor,
          remote_actor,
          "outbox"
        )
        remote_inbox = subscription_endpoint(
          actor_doc["inbox"]?.try(&.as_s?).to_s,
          target.remote_actor,
          remote_actor,
          "inbox"
        )
        key = "ocawe:federation:follow:#{remote_actor}"

        if existing = @federation_kv.get(key).try { |raw| JSON.parse(raw).as_h }
          status = existing["status"]?.try(&.as_s?).to_s
          if status == "active" || status == "following"
            refreshed = false
            existing_outbox = existing["remote_outbox"]?.try(&.as_s?).to_s
            existing_inbox = existing["remote_inbox"]?.try(&.as_s?).to_s
            if should_replace_subscription_endpoint?(existing_outbox, target.remote_actor, remote_actor, "outbox") && !remote_outbox.empty?
              existing["remote_outbox"] = Aptok.json(remote_outbox)
              refreshed = true
            end
            if should_replace_subscription_endpoint?(existing_inbox, target.remote_actor, remote_actor, "inbox") && !remote_inbox.empty?
              existing["remote_inbox"] = Aptok.json(remote_inbox)
              refreshed = true
            end
            if refreshed
              existing["updated_at"] = Aptok.json(Aptok.now)
              @federation_kv.set(key, existing.to_json)
            end
            return existing
          end
        end

        record = JSON.parse({
          "id"             => "#{@settings.federation.local_actor}|#{remote_actor}",
          "status"         => remote_inbox.empty? ? "pending" : "following",
          "local_actor"    => @settings.federation.local_actor,
          "remote_actor"   => remote_actor,
          "remote_inbox"   => remote_inbox,
          "remote_outbox"  => remote_outbox,
          "queue"          => target.queue,
          "capabilities"   => {"activitypub" => true, "forgefed" => true},
          "cursor"         => "",
          "last_polled_at" => "",
          "error"          => "",
          "created_at"     => Aptok.now,
          "updated_at"     => Aptok.now,
        }.to_json).as_h
        @federation_kv.set(key, record.to_json)
        send_aptok_follow(record) unless remote_inbox.empty?
        record
      end

      private def parse_aptok_subscription_target(value : String) : AptokSubscriptionTarget
        normalized = value.strip
        raise "subscription target is required" if normalized.empty?

        if normalized.includes?("|")
          raise "subscription target must be an actor IRI or handle; resources are published by the local ActivityPub actor document"
        end

        if normalized.starts_with?("http://") || normalized.starts_with?("https://")
          return AptokSubscriptionTarget.new(normalized, normalized, infer_queue_from_actor(normalized))
        end

        actor, domain = parse_aptok_subscription_handle(normalized)
        resolved_actor = actor.empty? ? "order-queue" : actor
        AptokSubscriptionTarget.new(normalized, "https://#{domain}/actors/#{resolved_actor}", resolved_actor)
      end

      private def parse_aptok_subscription_handle(value : String) : Tuple(String, String)
        raw = value.starts_with?('@') ? value[1..] : value
        if idx = raw.index('@')
          actor = raw[0, idx].strip
          domain = raw[idx + 1, raw.size - idx - 1].strip
          raise "invalid subscription handle: #{value}" if actor.empty? || domain.empty?
          return {actor, domain}
        end
        raise "invalid subscription domain: #{value}" if raw.empty?
        {"", raw}
      end

      private def infer_activitypub_peer_endpoint(actor : String, endpoint : String) : String
        uri = URI.parse(actor)
        path = uri.path || ""
        if path.starts_with?("/actors/")
          port = uri.port ? ":#{uri.port}" : ""
          return "#{uri.scheme}://#{uri.host}#{port}/#{endpoint}"
        end

        marker = "/actor/"
        idx = path.index(marker)
        return "" unless idx

        handle = path[idx + marker.size, path.size - idx - marker.size]?.to_s
        return "" if handle.empty? || handle.includes?("/")

        port = uri.port ? ":#{uri.port}" : ""
        "#{uri.scheme}://#{uri.host}#{port}/#{endpoint}/#{handle}"
      rescue
        ""
      end

      private def subscription_endpoint(discovered : String, subscription_actor : String, remote_actor : String, endpoint : String) : String
        if should_replace_subscription_endpoint?(discovered, subscription_actor, remote_actor, endpoint)
          fallback = infer_activitypub_peer_endpoint(subscription_actor, endpoint)
          return fallback if URI.parse(subscription_actor).path.to_s.starts_with?("/actors/") && !fallback.empty?

          rewritten = rewrite_endpoint_origin(discovered, subscription_actor)
          return rewritten unless rewritten.empty?
          return fallback
        end
        discovered.strip
      rescue
        discovered.strip
      end

      private def should_replace_subscription_endpoint?(discovered : String, subscription_actor : String, remote_actor : String, endpoint : String) : Bool
        fallback = infer_activitypub_peer_endpoint(subscription_actor, endpoint)
        return false if fallback.empty?
        value = discovered.strip
        return true if value.empty?

        discovered_uri = URI.parse(value)
        fallback_uri = URI.parse(fallback)
        discovered_host = discovered_uri.host.to_s.downcase
        fallback_host = fallback_uri.host.to_s.downcase
        return false if discovered_host == fallback_host
        container_local_host?(discovered_host) || actor_endpoint_uses_different_origin?(value, remote_actor, fallback)
      rescue
        false
      end

      private def container_local_host?(host : String) : Bool
        return true if host.empty?
        return true if host == "localhost" || host == "127.0.0.1" || host == "::1"
        !host.includes?(".")
      end

      private def rewrite_endpoint_origin(endpoint : String, subscription_actor : String) : String
        endpoint_uri = URI.parse(endpoint)
        subscription_uri = URI.parse(subscription_actor)
        return "" if endpoint_uri.path.to_s.empty? || subscription_uri.host.to_s.empty?

        port = subscription_uri.port ? ":#{subscription_uri.port}" : ""
        query = endpoint_uri.query ? "?#{endpoint_uri.query}" : ""
        fragment = endpoint_uri.fragment ? "##{endpoint_uri.fragment}" : ""
        "#{subscription_uri.scheme}://#{subscription_uri.host}#{port}#{endpoint_uri.path}#{query}#{fragment}"
      rescue
        ""
      end

      private def actor_endpoint_uses_different_origin?(endpoint : String, remote_actor : String, fallback : String) : Bool
        endpoint_uri = URI.parse(endpoint)
        actor_uri = URI.parse(remote_actor)
        fallback_uri = URI.parse(fallback)
        endpoint_host = endpoint_uri.host.to_s.downcase
        actor_host = actor_uri.host.to_s.downcase
        fallback_host = fallback_uri.host.to_s.downcase
        !actor_host.empty? && endpoint_host == actor_host && endpoint_host != fallback_host && container_local_host?(endpoint_host)
      rescue
        false
      end

      private def start_federation_poller : Nil
        interval = @settings.federation.s2s_poll_interval_seconds
        return if interval <= 0

        STDERR.puts "[federation] starting pollers interval=#{interval}s"

        spawn do
          loop do
            begin
              context = aptok_federation.create_context
              context.process_queued_inbox_activities(limit: 25)
              context.process_queued_activities(limit: 25)
            rescue ex
              STDERR.puts "[federation] queue cycle failed: #{ex.message}"
            end
            sleep interval.seconds
          end
        end

        spawn do
          loop do
            begin
              run_federation_poll_cycle
            rescue ex
              STDERR.puts "[federation] poll cycle failed: #{ex.message}"
            end
            sleep interval.seconds
          end
        end
      end

      private def run_federation_poll_cycle : Nil
        @federation_kv.list("ocawe:federation:follow:").each do |entry|
          follow = JSON.parse(entry.value).as_h
          remote_actor = follow["remote_actor"]?.try(&.as_s?).to_s
          remote_outbox = follow["remote_outbox"]?.try(&.as_s?).to_s
          if remote_actor.empty? || remote_outbox.empty?
            STDERR.puts "[federation] poll skipped remote_actor=#{remote_actor.empty? ? "(empty)" : remote_actor} remote_outbox=#{remote_outbox.empty? ? "(empty)" : remote_outbox}"
            next
          end

          begin
            ctx = aptok_federation.create_context
            STDERR.puts "[federation] polling remote_actor=#{remote_actor} outbox=#{remote_outbox}"
            collection = fetch_activitypub_collection(remote_outbox) ||
                         ctx.lookup_object(remote_outbox, Aptok::LookupObjectOptions.new(cross_origin: "trust"))
            activities = collection ? ctx.traverse_collection(collection, 250) : [] of Aptok::JsonMap
            activities = ordered_collection_items(collection) if activities.empty? && collection
            STDERR.puts "[federation] poll fetched remote_actor=#{remote_actor} activities=#{activities.size}"
            activities.each do |activity|
              activity_id = activity["id"]?.try(&.as_s?).to_s
              if activity_id.empty?
                STDERR.puts "[federation] polled activity skipped: missing id"
                next
              end
              seen_key = "ocawe:federation:seen:#{remote_actor}:#{activity_id}"
              if @federation_kv.get(seen_key)
                STDERR.puts "[federation] polled activity already seen id=#{activity_id}"
                next
              end

              STDERR.puts "[federation] processing polled activity id=#{activity_id} type=#{activity["type"]?.try(&.as_s?).to_s}"
              @federation_kv.set(seen_key, Aptok.now) if process_polled_activity(follow, activity)
            end

            update_aptok_follow_state(remote_actor, error: "", last_polled_at: Aptok.now)
          rescue ex
            STDERR.puts "[federation] poll failed remote_actor=#{remote_actor}: #{ex.message || ex.class.name}"
            update_aptok_follow_state(remote_actor, error: ex.message || ex.class.name, last_polled_at: Aptok.now)
          end
        end
      end

      private def fetch_activitypub_collection(iri : String) : Aptok::JsonMap?
        headers = ::HTTP::Headers{
          "Accept" => "application/activity+json, application/ld+json, application/json",
        }
        response = ::HTTP::Client.get(iri, headers: headers)
        unless response.status_code >= 200 && response.status_code < 300
          STDERR.puts "[federation] outbox fetch failed HTTP #{response.status_code}: #{response.body}"
          return nil
        end

        JSON.parse(response.body).as_h?
      rescue ex
        STDERR.puts "[federation] outbox fetch failed: #{ex.message || ex.class.name}"
        nil
      end

      private def ordered_collection_items(collection : Aptok::JsonMap) : Array(Aptok::JsonMap)
        activities = [] of Aptok::JsonMap
        raw_items = collection["orderedItems"]?.try(&.as_a?) || collection["items"]?.try(&.as_a?)
        return activities unless raw_items

        raw_items.each do |item|
          activity = item.as_h?
          activities << activity if activity
        end
        activities
      end

      private def update_aptok_follow_state(remote_actor : String, status : String? = nil, cursor : String? = nil, last_polled_at : String? = nil, error : String? = nil) : Nil
        key = "ocawe:federation:follow:#{remote_actor}"
        record = @federation_kv.get(key).try { |raw| JSON.parse(raw).as_h } || Aptok::JsonMap.new
        record["status"] = Aptok.json(status) if status
        record["cursor"] = Aptok.json(cursor) if cursor
        record["last_polled_at"] = Aptok.json(last_polled_at) if last_polled_at
        record["error"] = Aptok.json(error) if error
        record["updated_at"] = Aptok.json(Aptok.now)
        @federation_kv.set(key, record.to_json)
      end

      private def send_aptok_follow(record : Hash(String, JSON::Any)) : Nil
        local_actor = record["local_actor"]?.try(&.as_s?).to_s
        remote_actor = record["remote_actor"]?.try(&.as_s?).to_s
        remote_inbox = record["remote_inbox"]?.try(&.as_s?).to_s
        return if local_actor.empty? || remote_actor.empty? || remote_inbox.empty?

        follow = Aptok.follow(
          "#{local_actor}/activities/follow-#{Random::Secure.hex(12)}",
          local_actor,
          remote_actor,
          to: [remote_actor],
          target: remote_actor
        )
        append_aptok_outbox_event(local_actor, follow, "outbox-follow-#{Random::Secure.hex(12)}")
        delivery = Aptok::DeliveryConfig.new(
          inbox: remote_inbox,
          actor: local_actor,
          target: remote_actor,
          actor_ids: [remote_actor]
        )
        Aptok::Transport.new.deliver!(delivery, follow, local_actor_key_pair(local_actor))
      rescue ex
        remote_actor_for_error = remote_actor || ""
        update_aptok_follow_state(remote_actor_for_error, status: "pending", error: ex.message || ex.class.name) unless remote_actor_for_error.empty?
        STDERR.puts "[federation] follow delivery failed for #{remote_actor_for_error}: #{ex.message || ex.class.name}"
      end
    end
  end
end
