require "file_utils"
require "json"

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
      read_records(path)
        .select { |record| matches?(record, scope, kind, active_only) }
        .map { |record| include_values ? record : public_record(record) }
    end

    def value(name : String, path : String = store_path) : String?
      secret_name = validate_name(name)
      read_records(path).find { |record| record["name"]?.try(&.as_s?) == secret_name }
        .try(&.["value"]?)
        .try(&.as_s?)
    end

    def delete(name : String, path : String = store_path) : Bool
      secret_name = validate_name(name)
      records = read_records(path)
      remaining = records.reject { |record| record["name"]?.try(&.as_s?) == secret_name }
      return false if remaining.size == records.size

      write_records(remaining, path)
      true
    end

    def store_path : String
      if explicit = ENV["OCAWE_SECRETS_FILE"]?
        return File.expand_path(explicit) unless explicit.empty?
      end
      if dir = ENV["OCAWE_SECRETS_DIR"]?
        return File.expand_path(File.join(dir, "secrets.json")) unless dir.empty?
      end
      if results = ENV["ORATOR_RESULTS_DIR"]?
        return File.expand_path(File.join(results, "secrets", "secrets.json")) unless results.empty?
      end
      File.expand_path(DEFAULT_FILE)
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
