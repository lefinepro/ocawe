require "rcl"
require "../config/settings"

module OcaweCore
  module Utils
    module ConfigParser
      DEFAULT_RCL_PATH = "ocawe.config.rcl"

      # Parses a key=value assignment line, handling quoted values
      def self.parse_assignment(line : String) : Tuple(String?, String)
        parts = line.split("=", 2)
        return {nil, ""} if parts.size < 2
        key = parts[0].strip
        raw = parts[1].strip
        value = unquote_value(raw)
        {key, value}
      end

      # Removes quotes from a string value if present
      def self.unquote_value(value : String) : String
        raw = value
        if raw.starts_with?('"') && raw.ends_with?('"') && raw.size >= 2
          return raw[1, raw.size - 2]
        elsif raw.starts_with?('\'') && raw.ends_with?('\'') && raw.size >= 2
          return raw[1, raw.size - 2]
        end
        raw
      end

      # Loads environment variables from a .env file
      def self.load_dotenv(path : String = ".env") : Nil
        return unless File.exists?(path)

        File.each_line(path) do |line|
          raw = line.strip
          next if raw.empty? || raw.starts_with?("#")

          eq_index = raw.index('=')
          next unless eq_index

          key = raw[0, eq_index].strip
          value = raw[eq_index + 1, raw.size - eq_index - 1].strip
          next if key.empty? || ENV.has_key?(key)

          ENV[key] = unquote_value(value)
        end
      end

      def self.load_settings(default_settings : Ocawe::Config::Settings, rcl_path : String? = nil) : Ocawe::Config::Settings
        explicit = rcl_path || ENV["OCAWE_CONFIG_RCL"]?
        explicit_path = explicit && !explicit.to_s.strip.empty? ? explicit.to_s.strip : nil
        path = if explicit_path
                 explicit_path
               elsif File.exists?(DEFAULT_RCL_PATH)
                 DEFAULT_RCL_PATH
               else
                 nil
               end
        return default_settings unless path

        resolved = path
        raise "RCL config file not found: #{resolved}" unless File.exists?(resolved)

        begin
          doc = parse_rcl_with_legacy_api_support(resolved)
          apply_rcl_settings(default_settings, document_to_h(doc))
        rescue ex
          raise ex if explicit_path
          STDERR.puts "[ocawe] warning: failed to parse #{resolved}: #{ex.message}; using defaults"
          default_settings
        end
      end

      private def self.parse_rcl_with_legacy_api_support(path : String) : RCL::Document
        content = File.read(path)
        begin
          RCL.parse_string(content)
        rescue ex
          normalized = normalize_legacy_api_assignment(content)
          raise ex if normalized == content
          RCL.parse_string(normalized)
        end
      end

      # Backward-compatible support for root `api = "classic"|["classic","federation"]`.
      # RCL configs historically allowed a root api assignment; rewrite it to the block shape accepted by rcl.cr.
      private def self.normalize_legacy_api_assignment(content : String) : String
        lines = content.lines
        changed = false
        normalized = lines.map do |line|
          stripped = line.strip
          if stripped.starts_with?("api") && (eq = stripped.index('='))
            key = stripped[0, eq].strip
            value = stripped[eq + 1, stripped.size - eq - 1].strip
            if key == "api" && !value.empty?
              changed = true
              "api do\n  value = #{value}\nend\n"
            else
              line
            end
          else
            line
          end
        end
        changed ? normalized.join : content
      end
    end
  end
end

require "./config_parser_helpers"
