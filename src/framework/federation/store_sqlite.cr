module Cogni
  module Federation
    module Store
      class SQLite < Base
        @db : DB::Database

        def initialize(@path : String)
          ensure_parent_dir!(@path)
          @db = DB.open("sqlite3:#{@path}")
          @lock = Mutex.new
          migrate!
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
          @lock.synchronize do
            @db.exec(
              <<-SQL,
              INSERT INTO federation_follows (
                id, local_actor, remote_actor, queue, capabilities_json, status,
                remote_inbox, remote_outbox, remote_shared_inbox, remote_public_key_id, remote_public_key_pem, follow_activity_id,
                cursor, last_polled_at, error, created_at, updated_at
              )
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              ON CONFLICT(local_actor, remote_actor) DO UPDATE SET
                queue = excluded.queue, capabilities_json = excluded.capabilities_json, status = excluded.status,
                remote_inbox = excluded.remote_inbox, remote_outbox = excluded.remote_outbox, remote_shared_inbox = excluded.remote_shared_inbox,
                remote_public_key_id = excluded.remote_public_key_id, remote_public_key_pem = excluded.remote_public_key_pem, follow_activity_id = excluded.follow_activity_id,
                updated_at = excluded.updated_at
              SQL
              id, local_actor, remote_actor, queue, capabilities.to_json, status,
              remote_inbox.to_s, remote_outbox.to_s, remote_shared_inbox.to_s, remote_public_key_id.to_s, remote_public_key_pem.to_s, follow_activity_id.to_s,
              "", "", "", now, now
            )
            fetch_follow(local_actor, remote_actor)
          end
        end

        def list_following : Array(AnyHash)
          @lock.synchronize do
            rows = [] of AnyHash
            @db.query("SELECT id, status, local_actor, remote_actor, queue, capabilities_json, remote_inbox, remote_outbox, remote_shared_inbox, remote_public_key_id, remote_public_key_pem, follow_activity_id, cursor, last_polled_at, error, created_at, updated_at FROM federation_follows ORDER BY updated_at DESC, id ASC") do |rs|
              rs.each do
                rows << {
                  "id" => json_any(rs.read(String)), "status" => json_any(rs.read(String)), "local_actor" => json_any(rs.read(String)),
                  "remote_actor" => json_any(rs.read(String)), "queue" => json_any(rs.read(String)), "capabilities" => parse_json(rs.read(String)),
                  "remote_inbox" => json_any(rs.read(String)), "remote_outbox" => json_any(rs.read(String)), "remote_shared_inbox" => json_any(rs.read(String)),
                  "remote_public_key_id" => json_any(rs.read(String)), "remote_public_key_pem" => json_any(rs.read(String)),
                  "follow_activity_id" => json_any(rs.read(String)), "cursor" => json_any(rs.read(String)), "last_polled_at" => json_any(rs.read(String)),
                  "error" => json_any(rs.read(String)),
                  "created_at" => json_any(rs.read(String)), "updated_at" => json_any(rs.read(String)),
                } of String => JSON::Any
              end
            end
            rows
          end
        end

        def upsert_follow_sync_state(
          remote_actor : String,
          status : String? = nil,
          cursor : String? = nil,
          last_polled_at : String? = nil,
          error : String? = nil
        ) : Nil
          @lock.synchronize do
            @db.exec(
              <<-SQL,
              UPDATE federation_follows
              SET
                status = COALESCE(?, status),
                cursor = COALESCE(?, cursor),
                last_polled_at = COALESCE(?, last_polled_at),
                error = COALESCE(?, error),
                updated_at = ?
              WHERE remote_actor = ?
              SQL
              status, cursor, last_polled_at, error, utc_now, remote_actor
            )
          end
        end

        def subscribed?(remote_actor : String) : Bool
          @lock.synchronize do
            @db.query_one?(
              "SELECT 1 FROM federation_follows WHERE remote_actor = ? AND status IN ('active','pending') LIMIT 1",
              remote_actor,
              as: Int64
            ) != nil
          end
        end

        def activity_seen?(remote_actor : String, activity_id : String) : Bool
          @lock.synchronize do
            @db.query_one?("SELECT 1 FROM federation_seen_activities WHERE remote_actor = ? AND activity_id = ? LIMIT 1", remote_actor, activity_id, as: Int64) != nil
          end
        end

        def mark_activity_seen(remote_actor : String, activity_id : String, seen_at : String) : Nil
          @lock.synchronize do
            @db.exec(
              "INSERT OR IGNORE INTO federation_seen_activities (remote_actor, activity_id, seen_at) VALUES (?, ?, ?)",
              remote_actor, activity_id, seen_at
            )
          end
        end

        def append_inbox_event(actor : String, activity_type : String, payload : AnyHash, received_at : String) : AnyHash
          payload_json = payload.to_json
          @lock.synchronize do
            @db.exec("INSERT INTO federation_inbox_events (actor, activity_type, payload_json, received_at) VALUES (?, ?, ?, ?)", actor, activity_type, payload_json, received_at)
          end
          {"actor" => json_any(actor), "activity" => json_any(activity_type), "payload" => JSON.parse(payload_json), "received_at" => json_any(received_at)} of String => JSON::Any
        end

        def append_outbox_event(activity : AnyHash, event_id : String, published_at : String) : AnyHash
          activity_json = activity.to_json
          @lock.synchronize do
            @db.exec("INSERT INTO federation_outbox_events (event_id, activity_json, published_at) VALUES (?, ?, ?)", event_id, activity_json, published_at)
          end
          {"id" => json_any(event_id), "published_at" => json_any(published_at), "activity" => JSON.parse(activity_json)} of String => JSON::Any
        end

        def list_outbox_events : Array(AnyHash)
          @lock.synchronize do
            rows = [] of AnyHash
            @db.query("SELECT event_id, activity_json, published_at FROM federation_outbox_events ORDER BY id DESC") do |rs|
              rs.each do
                rows << {"id" => json_any(rs.read(String)), "published_at" => json_any(rs.read(String)), "activity" => parse_json(rs.read(String))} of String => JSON::Any
              end
            end
            rows
          end
        end

        private def migrate! : Nil
          @lock.synchronize do
            @db.exec <<-SQL
            CREATE TABLE IF NOT EXISTS federation_follows (
              id TEXT PRIMARY KEY, local_actor TEXT NOT NULL, remote_actor TEXT NOT NULL, queue TEXT NOT NULL, capabilities_json TEXT NOT NULL,
              status TEXT NOT NULL,
              remote_inbox TEXT NOT NULL DEFAULT '', remote_outbox TEXT NOT NULL DEFAULT '', remote_shared_inbox TEXT NOT NULL DEFAULT '',
              remote_public_key_id TEXT NOT NULL DEFAULT '', remote_public_key_pem TEXT NOT NULL DEFAULT '', follow_activity_id TEXT NOT NULL DEFAULT '',
              cursor TEXT NOT NULL DEFAULT '', last_polled_at TEXT NOT NULL DEFAULT '', error TEXT NOT NULL DEFAULT '',
              created_at TEXT NOT NULL, updated_at TEXT NOT NULL, UNIQUE(local_actor, remote_actor)
            )
            SQL
            ensure_column!("federation_follows", "remote_inbox", "TEXT NOT NULL DEFAULT ''")
            ensure_column!("federation_follows", "remote_outbox", "TEXT NOT NULL DEFAULT ''")
            ensure_column!("federation_follows", "remote_shared_inbox", "TEXT NOT NULL DEFAULT ''")
            ensure_column!("federation_follows", "remote_public_key_id", "TEXT NOT NULL DEFAULT ''")
            ensure_column!("federation_follows", "remote_public_key_pem", "TEXT NOT NULL DEFAULT ''")
            ensure_column!("federation_follows", "follow_activity_id", "TEXT NOT NULL DEFAULT ''")
            ensure_column!("federation_follows", "cursor", "TEXT NOT NULL DEFAULT ''")
            ensure_column!("federation_follows", "last_polled_at", "TEXT NOT NULL DEFAULT ''")
            ensure_column!("federation_follows", "error", "TEXT NOT NULL DEFAULT ''")
            @db.exec("CREATE INDEX IF NOT EXISTS idx_federation_follows_remote_actor ON federation_follows(remote_actor)")
            @db.exec <<-SQL
            CREATE TABLE IF NOT EXISTS federation_inbox_events (
              id INTEGER PRIMARY KEY AUTOINCREMENT, actor TEXT NOT NULL, activity_type TEXT NOT NULL, payload_json TEXT NOT NULL, received_at TEXT NOT NULL
            )
            SQL
            @db.exec("CREATE INDEX IF NOT EXISTS idx_federation_inbox_received_at ON federation_inbox_events(received_at)")
            @db.exec <<-SQL
            CREATE TABLE IF NOT EXISTS federation_outbox_events (
              id INTEGER PRIMARY KEY AUTOINCREMENT, event_id TEXT NOT NULL UNIQUE, activity_json TEXT NOT NULL, published_at TEXT NOT NULL
            )
            SQL
            @db.exec("CREATE INDEX IF NOT EXISTS idx_federation_outbox_published_at ON federation_outbox_events(published_at)")
            @db.exec <<-SQL
            CREATE TABLE IF NOT EXISTS federation_seen_activities (
              id INTEGER PRIMARY KEY AUTOINCREMENT, remote_actor TEXT NOT NULL, activity_id TEXT NOT NULL, seen_at TEXT NOT NULL,
              UNIQUE(remote_actor, activity_id)
            )
            SQL
            @db.exec("CREATE INDEX IF NOT EXISTS idx_federation_seen_activities_remote ON federation_seen_activities(remote_actor)")
          end
        end

        private def fetch_follow(local_actor : String, remote_actor : String) : AnyHash
          @db.query(
            "SELECT id, status, local_actor, remote_actor, queue, capabilities_json, remote_inbox, remote_outbox, remote_shared_inbox, remote_public_key_id, remote_public_key_pem, follow_activity_id, cursor, last_polled_at, error, created_at, updated_at FROM federation_follows WHERE local_actor = ? AND remote_actor = ? LIMIT 1",
            local_actor,
            remote_actor
          ) do |rs|
            rs.each do
              return {
                "id" => json_any(rs.read(String)), "status" => json_any(rs.read(String)), "local_actor" => json_any(rs.read(String)),
                "remote_actor" => json_any(rs.read(String)), "queue" => json_any(rs.read(String)), "capabilities" => parse_json(rs.read(String)),
                "remote_inbox" => json_any(rs.read(String)), "remote_outbox" => json_any(rs.read(String)), "remote_shared_inbox" => json_any(rs.read(String)),
                "remote_public_key_id" => json_any(rs.read(String)), "remote_public_key_pem" => json_any(rs.read(String)),
                "follow_activity_id" => json_any(rs.read(String)), "cursor" => json_any(rs.read(String)), "last_polled_at" => json_any(rs.read(String)),
                "error" => json_any(rs.read(String)),
                "created_at" => json_any(rs.read(String)), "updated_at" => json_any(rs.read(String)),
              } of String => JSON::Any
            end
          end
          raise "failed to fetch follow record"
        end

        private def ensure_column!(table : String, column : String, type_sql : String) : Nil
          columns = @db.query_all("PRAGMA table_info(#{table})", as: {Int64, String, String, Int64, String?, Int64})
          found = columns.any? { |row| row[1] == column }
          return if found
          @db.exec("ALTER TABLE #{table} ADD COLUMN #{column} #{type_sql}")
        end

        private def ensure_parent_dir!(path : String) : Nil
          parent = ::File.dirname(path)
          return if parent.empty? || parent == "."
          Dir.mkdir_p(parent)
        end
      end
    end
  end
end
