require "digest/sha256"
require "json"
require "pg"

module Ocawe
  module ClientApiKeys
    extend self

    alias AnyHash = Hash(String, JSON::Any)

    PREFIX = "lf-"

    def required_for?(workflow_id : String) : Bool
      workflow_key = workflow_id.upcase.gsub(/[^A-Z0-9]+/, "_")
      enabled?(ENV["OCAWE_API_KEYS_REQUIRED"]?) ||
        enabled?(ENV["OCAWE_#{workflow_key}_API_KEYS_REQUIRED"]?)
    end

    def admin_key : String?
      value = ENV["OCAWE_API_KEYS_ADMIN_KEY"]?.to_s.strip
      if value.empty?
        key = ENV.keys.sort!.find do |name|
          name.starts_with?("OCAWE_") && name.ends_with?("_ADMIN_KEY")
        end
        value = key ? ENV[key].strip : ""
      end
      value.empty? ? nil : value
    end

    private def enabled?(value : String?) : Bool
      value.to_s.downcase.in?("1", "true", "yes")
    end

    def create(workflow_id : String, label : String = "") : AnyHash
      ensure_schema
      id = "key_#{Random::Secure.hex(12)}"
      token = "#{PREFIX}#{Random::Secure.hex(32)}"
      now = Time.utc.to_rfc3339
      db = PG.connect(dsn)
      begin
        db.exec(<<-SQL, id, workflow_id, label, token_hash(token), now)
          INSERT INTO ocawe_api_keys
            (id, workflow_id, label, token_hash, active, created_at, updated_at)
          VALUES ($1, $2, $3, $4, TRUE, $5::timestamptz, $5::timestamptz)
        SQL
      ensure
        db.close
      end
      {
        "id"          => json(id),
        "workflow_id" => json(workflow_id),
        "label"       => json(label),
        "active"      => json(true),
        "created_at"  => json(now),
        "token"       => json(token),
      }
    end

    def list(workflow_id : String? = nil) : Array(JSON::Any)
      ensure_schema
      records = [] of JSON::Any
      db = PG.connect(dsn)
      begin
        db.query("SELECT id, workflow_id, label, active, created_at::text, updated_at::text FROM ocawe_api_keys ORDER BY created_at DESC") do |rs|
          rs.each do
            record = {
              "id"          => json(rs.read(String)),
              "workflow_id" => json(rs.read(String)),
              "label"       => json(rs.read(String)),
              "active"      => json(rs.read(Bool)),
              "created_at"  => json(rs.read(String)),
              "updated_at"  => json(rs.read(String)),
            } of String => JSON::Any
            next if workflow_id && record["workflow_id"].as_s != workflow_id
            records << JSON.parse(record.to_json)
          end
        end
      ensure
        db.close
      end
      records
    end

    def revoke(id : String) : Bool
      ensure_schema
      db = PG.connect(dsn)
      begin
        result = db.exec("UPDATE ocawe_api_keys SET active = FALSE, updated_at = NOW() WHERE id = $1 AND active = TRUE", id)
        result.rows_affected > 0
      ensure
        db.close
      end
    end

    def valid?(token : String, workflow_id : String) : Bool
      return false unless token.starts_with?(PREFIX)
      ensure_schema
      db = PG.connect(dsn)
      begin
        db.query("SELECT token_hash FROM ocawe_api_keys WHERE workflow_id = $1 AND active = TRUE", workflow_id) do |rs|
          rs.each do
            return true if secure_equals(token_hash(token), rs.read(String))
          end
        end
      ensure
        db.close
      end
      false
    end

    private def dsn : String
      value = (ENV["OCAWE_API_KEYS_DSN"]? || ENV["OCAWE_SECRETS_DSN"]? || ENV["OCAWE_SECRETS_DATABASE_URL"]?).to_s.strip
      raise "Ocawe API-key storage is not configured" if value.empty?
      value
    end

    private def ensure_schema : Nil
      db = PG.connect(dsn)
      begin
        db.exec(<<-SQL)
          CREATE TABLE IF NOT EXISTS ocawe_api_keys (
            id TEXT PRIMARY KEY,
            workflow_id TEXT NOT NULL,
            label TEXT NOT NULL DEFAULT '',
            token_hash TEXT NOT NULL,
            active BOOLEAN NOT NULL DEFAULT TRUE,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
          )
        SQL
      ensure
        db.close
      end
    end

    private def token_hash(token : String) : String
      Digest::SHA256.hexdigest(token)
    end

    private def secure_equals(left : String, right : String) : Bool
      return false unless left.bytesize == right.bytesize
      mismatch = 0_u8
      left.bytes.zip(right.bytes) { |a, b| mismatch |= a ^ b }
      mismatch == 0_u8
    end

    private def json(value) : JSON::Any
      JSON.parse(value.to_json)
    end
  end
end
