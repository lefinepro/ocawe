require "file_utils"
require "json"
require "pg"

module Ocawe
  module Secrets
    extend self

    DEFAULT_FILE = "./.ocawe/secrets.json"

    alias Metadata = Hash(String, String)

    def put(
      name : String,
      value : String,
      scope : String = "",
      kind : String = "",
      metadata : Metadata = Metadata.new,
      active : Bool = true,
      path : String = store_path,
    ) : JSON::Any
      secret_name = validate_name(name)
      raise "secret value must not be empty" if value.empty?

      return postgres_put(secret_name, value, scope, kind, metadata, active) if postgres_dsn

      now = Time.utc.to_rfc3339
      records = read_records(path)
      existing = records.find { |record| record["name"]?.try(&.as_s?) == secret_name }
      record = existing || JSON.parse({
        "name"       => secret_name,
        "created_at" => now,
      }.to_json)
      hash = record.as_h
      hash["value"] = JSON.parse(value.to_json)
      hash["scope"] = JSON.parse(scope.to_json)
      hash["kind"] = JSON.parse(kind.to_json)
      hash["metadata"] = JSON.parse(metadata.to_json)
      hash["active"] = JSON.parse(active.to_json)
      hash["updated_at"] = JSON.parse(now.to_json)

      records << record unless existing
      write_records(records, path)
      public_record(record)
    end

    def list(
      scope : String? = nil,
      kind : String? = nil,
      include_values : Bool = false,
      active_only : Bool = false,
      path : String = store_path,
    ) : Array(JSON::Any)
      return postgres_list(scope, kind, include_values, active_only) if postgres_dsn

      read_records(path)
        .select { |record| matches?(record, scope, kind, active_only) }
        .map { |record| include_values ? record : public_record(record) }
    end

    def value(name : String, path : String = store_path) : String?
      secret_name = validate_name(name)
      if postgres_dsn
        postgres_list(nil, nil, true, false).find { |record| record["name"]?.try(&.as_s?) == secret_name }
          .try { |record| record["value"]?.try(&.as_s?) }
      else
      read_records(path).find { |record| record["name"]?.try(&.as_s?) == secret_name }
        .try(&.["value"]?)
        .try(&.as_s?)
      end
    end

    def delete(name : String, path : String = store_path) : Bool
      secret_name = validate_name(name)
      if postgres_dsn
        ensure_postgres_schema
        db = PG.connect(postgres_dsn.not_nil!)
        begin
          result = db.exec("DELETE FROM ocawe_secrets WHERE name = $1", secret_name)
          result.rows_affected > 0
        ensure
          db.close
        end
      else
      records = read_records(path)
      remaining = records.reject { |record| record["name"]?.try(&.as_s?) == secret_name }
      return false if remaining.size == records.size

      write_records(remaining, path)
      true
      end
    end

    def store_path : String
      if explicit = ENV["OCAWE_SECRETS_FILE"]?
        return File.expand_path(explicit) unless explicit.empty?
      end
      if dir = ENV["OCAWE_SECRETS_DIR"]?
        return File.expand_path(File.join(dir, "secrets.json")) unless dir.empty?
      end
      if results = ENV["OCAWE_RESULTS_DIR"]?
        return File.expand_path(File.join(results, "secrets", "secrets.json")) unless results.empty?
      end
      File.expand_path(DEFAULT_FILE)
    end

    private def postgres_dsn : String?
      value = (ENV["OCAWE_SECRETS_DSN"]? || ENV["OCAWE_SECRETS_DATABASE_URL"]?).to_s.strip
      value.empty? ? nil : value
    end

    private def ensure_postgres_schema : Nil
      db = PG.connect(postgres_dsn.not_nil!)
      begin
        db.exec(<<-SQL)
          CREATE TABLE IF NOT EXISTS ocawe_secrets (
            name TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            scope TEXT NOT NULL DEFAULT '',
            kind TEXT NOT NULL DEFAULT '',
            metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
            active BOOLEAN NOT NULL DEFAULT TRUE,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
          )
        SQL
      ensure
        db.close
      end
    end

    private def postgres_put(
      name : String,
      value : String,
      scope : String,
      kind : String,
      metadata : Metadata,
      active : Bool,
    ) : JSON::Any
      ensure_postgres_schema
      now = Time.utc.to_rfc3339
      db = PG.connect(postgres_dsn.not_nil!)
      begin
        db.exec(<<-SQL, name, value, scope, kind, metadata.to_json, active, now)
          INSERT INTO ocawe_secrets
            (name, value, scope, kind, metadata, active, created_at, updated_at)
          VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7::timestamptz, $7::timestamptz)
          ON CONFLICT (name) DO UPDATE SET
            value = EXCLUDED.value,
            scope = EXCLUDED.scope,
            kind = EXCLUDED.kind,
            metadata = EXCLUDED.metadata,
            active = EXCLUDED.active,
            updated_at = EXCLUDED.updated_at
        SQL
      ensure
        db.close
      end
      public_record(JSON.parse({
        "name" => name, "scope" => scope, "kind" => kind,
        "metadata" => metadata, "active" => active,
        "created_at" => now, "updated_at" => now,
      }.to_json))
    end

    private def postgres_list(
      scope : String?,
      kind : String?,
      include_values : Bool,
      active_only : Bool,
    ) : Array(JSON::Any)
      ensure_postgres_schema
      records = [] of JSON::Any
      db = PG.connect(postgres_dsn.not_nil!)
      begin
        db.query(<<-SQL) do |rs|
          SELECT name, value, scope, kind, metadata::text,
                 active, created_at::text, updated_at::text
          FROM ocawe_secrets
          ORDER BY name
        SQL
          rs.each do
            record = JSON.parse({
              "name" => rs.read(String),
              "value" => rs.read(String),
              "scope" => rs.read(String),
              "kind" => rs.read(String),
              "metadata" => JSON.parse(rs.read(String)),
              "active" => rs.read(Bool),
              "created_at" => rs.read(String),
              "updated_at" => rs.read(String),
            }.to_json)
            next if scope && record["scope"].as_s != scope
            next if kind && record["kind"].as_s != kind
            next if active_only && !record["active"].as_bool
            records << (include_values ? record : public_record(record))
          end
        end
      ensure
        db.close
      end
      records
    end

    private def read_records(path : String) : Array(JSON::Any)
      return [] of JSON::Any unless File.file?(path)

      parsed = JSON.parse(File.read(path))
      if array = parsed.as_a?
        return array.compact_map { |record| record.as_h? ? record : nil }
      end
      if hash = parsed.as_h?
        return hash.map do |name, value|
          record = (value.as_h? || {} of String => JSON::Any).dup
          record["name"] = JSON.parse(name.to_json) unless record.has_key?("name")
          JSON.parse(record.to_json)
        end
      end
      [] of JSON::Any
    rescue
      [] of JSON::Any
    end

    private def write_records(records : Array(JSON::Any), path : String) : Nil
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, records.to_json)
      File.chmod(path, 0o600)
    end

    private def public_record(record : JSON::Any) : JSON::Any
      hash = record.as_h
      JSON.parse({
        "name"       => hash["name"]?,
        "scope"      => hash["scope"]?,
        "kind"       => hash["kind"]?,
        "metadata"   => hash["metadata"]?,
        "active"     => hash["active"]?,
        "created_at" => hash["created_at"]?,
        "updated_at" => hash["updated_at"]?,
      }.to_json)
    end

    private def matches?(record : JSON::Any, scope : String?, kind : String?, active_only : Bool) : Bool
      return false if scope && record["scope"]?.try(&.as_s?) != scope
      return false if kind && record["kind"]?.try(&.as_s?) != kind
      return false if active_only && record["active"]?.try(&.as_bool?) == false
      true
    end

    private def validate_name(name : String) : String
      value = name.strip
      raise "secret name must not be empty" if value.empty?
      raise "secret name is too long" if value.bytesize > 256
      raise "secret name contains control characters" if value.bytes.any? { |byte| byte < 0x20 || byte == 0x7f }
      raise "secret name contains traversal" if value.includes?("..")
      value
    end
  end
end
