require "../../vendor/rcl/src/rcl"
require "../config/settings"

module CogniCore
  module Utils
    module ConfigParser
      DEFAULT_RCL_PATH = "cogni.config.rcl"

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

      def self.load_settings(default_settings : Cogni::Config::Settings, rcl_path : String? = nil) : Cogni::Config::Settings
        explicit = rcl_path || ENV["COGNI_CONFIG_RCL"]?
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
          apply_rcl_settings(default_settings, doc.to_h)
        rescue ex
          raise ex if explicit_path
          STDERR.puts "[cogni] warning: failed to parse #{resolved}: #{ex.message}; using defaults"
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

      # Backward-compatible support for root `api = "mastra"|["mastra","lefine"]`.
      # Vendor RCL parser expects top-level blocks, so rewrite to an equivalent block.
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

      private def self.apply_rcl_settings(base : Cogni::Config::Settings, raw : Hash(String, RCL::Value)) : Cogni::Config::Settings
        root = raw["root"]?
        tree = root.is_a?(Hash(String, RCL::Value)) ? root : raw

        workflows = base.workflows
        if wf_raw = tree["workflows"]?
          if wf = wf_raw.as?(Hash(String, RCL::Value))
            preferred = string_or_nil(wf["preferred_workflows_root"]?) || workflows.preferred_workflows_root
            fallback = string_or_nil(wf["fallback_workflows_root"]?) || workflows.fallback_workflows_root
            workflows = Cogni::Config::WorkflowSettings.new(preferred, fallback)
          end
        end

        datasets = base.datasets
        if ds_raw = tree["datasets"]?
          if ds = ds_raw.as?(Hash(String, RCL::Value))
            adapter = string_or_nil(ds["adapter"]?) || datasets.adapter
            file_root = string_or_nil(ds["file_root"]?) || datasets.file_root
            datasets = Cogni::Config::DatasetSettings.new(adapter, file_root)
          end
        end

        federation = base.federation
        if fed_raw = tree["federation"]?
          if fed = fed_raw.as?(Hash(String, RCL::Value))
            adapter = string_or_nil(fed["adapter"]?) || federation.adapter
            sqlite_path = string_or_nil(fed["sqlite_path"]?) || federation.sqlite_path
            poll_interval = int32_or_nil(fed["s2s_poll_interval_seconds"]?) || federation.s2s_poll_interval_seconds
            http_timeout = int32_or_nil(fed["s2s_http_timeout_seconds"]?) || federation.s2s_http_timeout_seconds
            signatures_required = bool_or_nil(fed["signatures_required"]?)
            signatures_required = federation.signatures_required if signatures_required.nil?
            local_actor = string_or_nil(fed["local_actor"]?) || federation.local_actor
            local_key_id = string_or_nil(fed["local_key_id"]?) || federation.local_key_id
            local_private_key_path = string_or_nil(fed["local_private_key_path"]?) || federation.local_private_key_path
            federation = Cogni::Config::FederationSettings.new(
              adapter, sqlite_path, poll_interval, http_timeout, signatures_required.not_nil!, local_actor, local_key_id, local_private_key_path
            )
          end
        end

        api = base.api
        if api_raw = tree["api"]?
          parsed_api = parse_api_value(api_raw)
          api = Cogni::Config::ApiSettings.new(parsed_api) unless parsed_api.empty?
        end

        functions = base.functions
        if fn_raw = tree["functions"]?
          if fn = fn_raw.as?(Hash(String, RCL::Value))
            enabled = parse_functions_value(fn["enabled"]?)
            unless enabled.empty?
              available = Cogni::Config::DefaultFunctionHandlers.available
              resolved = {} of String => Cogni::Workflow::FunctionHandler
              enabled.each do |name|
                key = name.strip.downcase
                handler = available[key]?
                raise "unknown function handler in config.functions.enabled: #{name}" unless handler
                resolved[key] = handler
              end
              functions = resolved
            end
          end
        end

        Cogni::Config::Settings.new(
          workflows: workflows,
          node_kinds: base.node_kinds,
          datasets: datasets,
          federation: federation,
          api: api,
          functions: functions,
          workspace_bootstrap: base.workspace_bootstrap,
          mcp: base.mcp,
        )
      end

      private def self.string_or_nil(value : RCL::Value?) : String?
        value.is_a?(String) ? value : nil
      end

      private def self.int32_or_nil(value : RCL::Value?) : Int32?
        case value
        when Int32
          value
        when Int64
          value.to_i32
        when Float64
          value.to_i32
        when String
          parsed = value.to_i?
          parsed ? parsed.to_i32 : nil
        else
          nil
        end
      end

      private def self.bool_or_nil(value : RCL::Value?) : Bool?
        case value
        when Bool
          value
        when String
          normalized = value.strip.downcase
          return true if normalized == "true" || normalized == "1"
          return false if normalized == "false" || normalized == "0"
          nil
        else
          nil
        end
      end

      private def self.parse_api_value(value : RCL::Value) : Array(String)
        case value
        when String
          [value]
        when Array
          value.compact_map { |entry| entry.is_a?(String) ? entry : nil }
        when Hash(String, RCL::Value)
          nested = value["value"]?
          return [] of String unless nested
          parse_api_value(nested)
        else
          [] of String
        end
      end

      private def self.parse_functions_value(value : RCL::Value?) : Array(String)
        return [] of String unless value

        case value
        when String
          [value]
        when Array
          value.compact_map { |entry| entry.is_a?(String) ? entry : nil }
        when Hash(String, RCL::Value)
          nested = value["value"]?
          return [] of String unless nested
          parse_functions_value(nested)
        else
          [] of String
        end
      end
    end
  end
end
