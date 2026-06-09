require "rcl"
require "../config/settings"
require "../discovery/cawfile_loader"

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

        # 1. Explicit RCL path takes highest precedence
        if explicit_path
          raise "RCL config file not found: #{explicit_path}" unless File.exists?(explicit_path)
          doc = parse_rcl_with_legacy_api_support(explicit_path)
          return apply_rcl_settings(default_settings, document_to_h(doc))
        end

        # 2. Root Cawfile (mirrors ocawe.config.rcl settings)
        if cawfile_bundle = ACD::Discovery::CawfileLoader.load_root
          return apply_cawfile_settings(default_settings, cawfile_bundle)
        end

        # 3. Legacy ocawe.config.rcl fallback
        if File.exists?(DEFAULT_RCL_PATH)
          doc = parse_rcl_with_legacy_api_support(DEFAULT_RCL_PATH)
          return apply_rcl_settings(default_settings, document_to_h(doc))
        end

        default_settings
      rescue ex
        raise ex if explicit_path
        STDERR.puts "[ocawe] warning: failed to load settings: #{ex.message}; using defaults"
        default_settings
      end

      def self.load_start_settings(default_settings : Ocawe::Config::StartSettings) : Ocawe::Config::StartSettings
        if cawfile_bundle = ACD::Discovery::CawfileLoader.load_root
          start = cawfile_bundle.start_settings
          port = int32_or_nil(start["port"]?)
          workflows_root = string_or_nil(start["workflows_root"]?)
          return Ocawe::Config::StartSettings.new(
            port: port || default_settings.port,
            workflows_root: workflows_root || default_settings.workflows_root
          )
        end
        default_settings
      rescue ex
        STDERR.puts "[ocawe] warning: failed to load start settings from Cawfile: #{ex.message}; using defaults"
        default_settings
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
