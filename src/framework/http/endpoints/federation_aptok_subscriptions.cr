module ACD
  module Kemal
    class App
      private def bootstrap_federation_subscriptions : Nil
        # The very first outbound activity is the Follow below, and it has to be
        # signed, so the signing key must exist before any delivery is attempted
        # rather than being generated lazily under it.
        ensure_local_private_key(@settings.federation.local_private_key_path)

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
        remote_outbox = actor_doc["outbox"]?.try(&.as_s?).to_s
        remote_inbox = actor_doc["inbox"]?.try(&.as_s?).to_s
        key = "ocawe:federation:follow:#{remote_actor}"

        if existing = @federation_kv.get(key).try { |raw| JSON.parse(raw).as_h }
          status = existing["status"]?.try(&.as_s?).to_s
          if status == "active" || status == "following"
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
          # Kept so a subscription whose peer was not yet listening can be
          # resolved again on a later poll cycle.
          "target"         => target.name,
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
          raise "subscription target must be an actor IRI or handle; inbox is discovered through ActivityPub Follow"
        end

        if normalized.starts_with?("http://") || normalized.starts_with?("https://")
          return AptokSubscriptionTarget.new(normalized, normalized, infer_queue_from_actor(normalized))
        end

        actor, domain = parse_aptok_subscription_handle(normalized)
        resolved_actor = actor.empty? ? "order-queue" : actor

        # `@name@fedi.internal` never resolves through WebFinger: it names a peer
        # inside this deployment, so it is mapped through the internal peer table.
        internal_domain = @settings.federation.internal_domain
        if domain.downcase == internal_domain.strip.downcase
          actor_url = Ocawe::Federation::InternalDomain.actor_url(
            resolved_actor,
            @settings.federation.resolved_internal_peers,
            internal_domain
          )
          return AptokSubscriptionTarget.new(normalized, actor_url, resolved_actor)
        end

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

      private def start_federation_poller : Nil
        interval = @settings.federation.s2s_poll_interval_seconds
        return if interval <= 0

        spawn do
          loop do
            begin
              run_federation_poll_cycle
              aptok_federation.create_context.process_queued_inbox_activities(limit: 25)
              aptok_federation.create_context.process_queued_activities(limit: 25)
            rescue ex
              STDERR.puts "[federation] poll cycle failed: #{ex.message}"
            end
            sleep interval.seconds
          end
        end
      end

      private def run_federation_poll_cycle : Nil
        retry_unresolved_subscriptions
        retry_pending_follows

        @federation_kv.list("ocawe:federation:follow:").each do |entry|
          follow = JSON.parse(entry.value).as_h
          remote_actor = follow["remote_actor"]?.try(&.as_s?).to_s
          remote_outbox = follow["remote_outbox"]?.try(&.as_s?).to_s
          next if remote_actor.empty? || remote_outbox.empty?

          begin
            ctx = aptok_federation.create_context
            collection = ctx.lookup_object(remote_outbox, Aptok::LookupObjectOptions.new(cross_origin: "trust"))
            activities = collection ? ctx.traverse_collection(collection, 50) : [] of Aptok::JsonMap
            activities.each do |activity|
              activity_id = activity["id"]?.try(&.as_s?).to_s
              next if activity_id.empty?
              seen_key = "ocawe:federation:seen:#{remote_actor}:#{activity_id}"
              next if @federation_kv.get(seen_key)

              @federation_kv.set(seen_key, Aptok.now) if process_polled_activity(follow, activity)
            end

            update_aptok_follow_state(remote_actor, error: "", last_polled_at: Aptok.now)
          rescue ex
            update_aptok_follow_state(remote_actor, error: ex.message || ex.class.name, last_polled_at: Aptok.now)
          end
        end
      end

      # A peer that was not listening when subscriptions were bootstrapped leaves
      # a record without a `remote_inbox`, and an empty inbox is skipped by both
      # the follow retry and outbound delivery - the subscription would stay dead
      # until a restart. Re-resolving the stored target on every poll cycle picks
      # the peer up as soon as it answers.
      private def retry_unresolved_subscriptions : Nil
        @federation_kv.list("ocawe:federation:follow:").each do |entry|
          record = JSON.parse(entry.value).as_h
          next unless record["remote_inbox"]?.try(&.as_s?).to_s.empty?
          target = record["target"]?.try(&.as_s?).to_s
          next if target.empty?

          ensure_aptok_subscription(target)
        rescue ex
          STDERR.puts "[federation] subscription re-resolution failed: #{ex.message || ex.class.name}"
        end
      end

      # Subscriptions are bootstrapped before `Kemal.run` starts listening, so the
      # very first Follow is delivered while this runtime cannot yet serve its own
      # actor document. The peer then fails to resolve the signing key and answers
      # 401, which parks the record in `pending` - and `pending` records are
      # skipped by outbound delivery, so a runtime would never send anything again
      # without a restart. Retrying on every poll cycle recovers as soon as both
      # sides are listening; a Follow that is already `active`/`following` is left
      # untouched, so this never re-sends for a healthy subscription.
      private def retry_pending_follows : Nil
        @federation_kv.list("ocawe:federation:follow:").each do |entry|
          record = JSON.parse(entry.value).as_h
          next unless record["status"]?.try(&.as_s?).to_s == "pending"
          next if record["remote_inbox"]?.try(&.as_s?).to_s.empty?

          update_aptok_follow_state(
            record["remote_actor"]?.try(&.as_s?).to_s,
            status: "following",
            error: "",
          )
          send_aptok_follow(record)
        rescue ex
          STDERR.puts "[federation] pending follow retry failed: #{ex.message || ex.class.name}"
        end
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
