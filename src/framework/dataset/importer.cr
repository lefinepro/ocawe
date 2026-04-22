require "csv"
require "json"

module Cogni
  module Dataset
    module Importer
      extend self

      def load(
        source_path : String,
        format : String? = nil,
        base_dir : String? = nil,
        options : AnyHash? = nil
      ) : Array(AnyHash)
        resolved = resolve_path(source_path, base_dir)
        raise "dataset source file not found: #{resolved}" unless File.exists?(resolved)

        case normalize_format(format, resolved)
        when "json"
          load_json(File.read(resolved), resolved, options)
        when "csv"
          load_csv(File.read(resolved), resolved, options)
        else
          raise "unsupported dataset source format for #{resolved}"
        end
      end

      private def load_json(content : String, resolved : String, options : AnyHash?) : Array(AnyHash)
        parsed = JSON.parse(content)
        root_key = options.try { |value| value["root_key"]?.try(&.as_s?) }

        if root_key
          parsed_hash = parsed.as_h?
          nested = parsed_hash.try { |hash| hash[root_key]? }
          raise "dataset json source #{resolved} is missing root key '#{root_key}'" unless nested
          parsed = nested.not_nil!
        end

        as_hashes(parsed, resolved)
      end

      private def load_csv(content : String, resolved : String, options : AnyHash?) : Array(AnyHash)
        headers = options.try { |value| value["headers"]?.try(&.raw) } != false
        strip = options.try { |value| value["strip"]?.try(&.raw) } != false
        separator = options.try { |value| csv_separator(value["separator"]?) } || ','

        items = [] of AnyHash
        if headers
          csv = CSV.new(content, headers: true, strip: strip, separator: separator)
          csv.each do
            item = {} of String => JSON::Any
            csv.headers.each do |header|
              item[header] = infer_scalar(csv[header])
            end
            items << item
          end
        else
          CSV.each_row(content, separator: separator) do |row|
            item = {} of String => JSON::Any
            row.each_with_index do |value, idx|
              item["column_#{idx + 1}"] = infer_scalar(strip ? value.strip : value)
            end
            items << item
          end
        end

        items
      end

      private def as_hashes(parsed : JSON::Any, resolved : String) : Array(AnyHash)
        if array = parsed.as_a?
          return array.map do |entry|
            hash = entry.as_h?
            raise "dataset json source #{resolved} must contain objects" unless hash
            hash
          end
        end

        hash = parsed.as_h?
        raise "dataset json source #{resolved} must be an object or array of objects" unless hash
        [hash]
      end

      private def normalize_format(format : String?, resolved : String) : String
        explicit = format.to_s.strip.downcase
        return explicit unless explicit.empty?

        ext = File.extname(resolved).downcase
        case ext
        when ".json"
          "json"
        when ".csv"
          "csv"
        else
          ""
        end
      end

      private def resolve_path(source_path : String, base_dir : String?) : String
        stripped = source_path.strip
        raise "dataset source path is required" if stripped.empty?
        return File.expand_path(stripped) if stripped.starts_with?("/")
        File.expand_path(stripped, base_dir || Dir.current)
      end

      private def csv_separator(value : JSON::Any?) : Char?
        return nil unless value
        raw = value.as_s?
        return nil unless raw && raw.size == 1
        raw[0]
      end

      private def infer_scalar(value : String) : JSON::Any
        stripped = value.strip
        return JSON.parse("null") if stripped.downcase == "null"
        return JSON.parse("true") if stripped.downcase == "true"
        return JSON.parse("false") if stripped.downcase == "false"

        if stripped.matches?(/^-?\d+$/)
          return JSON.parse(stripped)
        end
        if stripped.matches?(/^-?\d+\.\d+$/)
          return JSON.parse(stripped)
        end
        if (stripped.starts_with?("{") && stripped.ends_with?("}")) || (stripped.starts_with?("[") && stripped.ends_with?("]"))
          parsed = JSON.parse(stripped)
          return parsed
        end

        JSON.parse(value.to_json)
      rescue
        JSON.parse(value.to_json)
      end
    end
  end
end
