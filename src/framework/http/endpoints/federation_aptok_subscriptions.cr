module ACD
  module Kemal
    class App
      private def bootstrap_federation_subscriptions : Nil
        @settings.federation.auto_subscribe.each do |entry|
          normalized = entry.strip
          next if normalized.empty?

          begin
            record = ensure_aptok_subscription(normalized)
            STDERR.puts "[federation] subscribed #{normalized} -> #{record["remote_actor"]?.try(&.as_s?) || normalized}"
          rescue ex
            STDERR.puts "[federation] auto_subscribe failed for #{normalized}: #{ex.message || ex.class.name}"
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

        record = JSON.parse({
          "id" => "#{@settings.federation.local_actor}|#{remote_actor}",
          "status" => "active",
          "local_actor" => @settings.federation.local_actor,
          "remote_actor" => remote_actor,
          "remote_inbox" => remote_inbox,
          "remote_outbox" => remote_outbox,
          "queue" => target.queue,
          "capabilities" => {"activitypub" => true, "forgefed" => true},
          "cursor" => "",
          "last_polled_at" => "",
          "error" => "",
          "created_at" => Aptok.now,
          "updated_at" => Aptok.now,
        }.to_json).as_h
        @federation_kv.set("cogni:federation:follow:#{remote_actor}", record.to_json)
        record
      end

      private def parse_aptok_subscription_target(value : String) : AptokSubscriptionTarget
        normalized = value.strip
        raise "subscription target is required" if normalized.empty?

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
            sleep interval
          end
        end
      end

      private def run_federation_poll_cycle : Nil
        @federation_kv.list("cogni:federation:follow:").each do |entry|
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
              seen_key = "cogni:federation:seen:#{remote_actor}:#{activity_id}"
              next if @federation_kv.get(seen_key)

              @federation_kv.set(seen_key, Aptok.now) if process_polled_activity(follow, activity)
            end

            update_aptok_follow_state(remote_actor, error: "", last_polled_at: Aptok.now)
          rescue ex
            update_aptok_follow_state(remote_actor, error: ex.message || ex.class.name, last_polled_at: Aptok.now)
          end
        end
      end

      private def update_aptok_follow_state(remote_actor : String, status : String? = nil, cursor : String? = nil, last_polled_at : String? = nil, error : String? = nil) : Nil
        key = "cogni:federation:follow:#{remote_actor}"
        record = @federation_kv.get(key).try { |raw| JSON.parse(raw).as_h } || Aptok::JsonMap.new
        record["status"] = Aptok.json(status) if status
        record["cursor"] = Aptok.json(cursor) if cursor
        record["last_polled_at"] = Aptok.json(last_polled_at) if last_polled_at
        record["error"] = Aptok.json(error) if error
        record["updated_at"] = Aptok.json(Aptok.now)
        @federation_kv.set(key, record.to_json)
      end

    end
  end
end
