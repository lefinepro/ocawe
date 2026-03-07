module ACD
  module Kemal
    class App
      private def start_federation_poller : Nil
        interval = @settings.federation.s2s_poll_interval_seconds
        return if interval <= 0

        spawn do
          loop do
            begin
              run_federation_poll_cycle
            rescue ex
              STDERR.puts "[federation] poll cycle failed: #{ex.message}"
            end
            sleep interval
          end
        end
      end

      private def run_federation_poll_cycle : Nil
        follows = @federation_store.list_following
        follows.each do |follow|
          remote_actor = follow["remote_actor"]?.try(&.as_s?).to_s
          status = follow["status"]?.try(&.as_s?).to_s
          remote_outbox = follow["remote_outbox"]?.try(&.as_s?).to_s
          next if remote_actor.empty? || remote_outbox.empty?
          next unless status == "active" || status == "pending"

          begin
            outbox_doc = fetch_jsonld_activity(remote_outbox, follow)
            activities = extract_activities_from_outbox(outbox_doc)
            newest_id = ""
            activities.each do |activity|
              activity_id = activity["id"]?.try(&.as_s?).to_s
              next if activity_id.empty?
              newest_id = activity_id if newest_id.empty?
              next if @federation_store.activity_seen?(remote_actor, activity_id)
              processed = process_polled_activity(follow, activity)
              if processed
                @federation_store.mark_activity_seen(remote_actor, activity_id, Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ"))
              end
            end

            @federation_store.upsert_follow_sync_state(
              remote_actor: remote_actor,
              cursor: newest_id.empty? ? nil : newest_id,
              last_polled_at: Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ"),
              error: ""
            )
          rescue ex
            @federation_store.upsert_follow_sync_state(
              remote_actor: remote_actor,
              last_polled_at: Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ"),
              error: ex.message || ex.class.name
            )
          end
        end
      end
    end
  end
end
