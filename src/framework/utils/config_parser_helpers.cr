module CogniCore
  module Utils
    module ConfigParser
      private def self.apply_rcl_settings(base : Cogni::Config::Settings, raw : Hash(String, RCL::Value)) : Cogni::Config::Settings
        root = raw["root"]?
        tree = root.is_a?(Hash(String, RCL::Value)) ? root : raw
        apply_credentials_env_overrides(tree["credentials"]?)

        workflows = base.workflows
        if wf_raw = tree["workflows"]?
          if wf = wf_raw.as?(Hash(String, RCL::Value))
            preferred = string_or_nil(wf["preferred_workflows_root"]?) || workflows.preferred_workflows_root
            workflows = Cogni::Config::WorkflowSettings.new(preferred)
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
            auto_subscribe = parse_string_list_value(fed["auto_subscribe"]?)
            auto_subscribe = federation.auto_subscribe if auto_subscribe.empty?
            poll_interval = int32_or_nil(fed["s2s_poll_interval_seconds"]?) || federation.s2s_poll_interval_seconds
            http_timeout = int32_or_nil(fed["s2s_http_timeout_seconds"]?) || federation.s2s_http_timeout_seconds
            signatures_required = bool_or_nil(fed["signatures_required"]?)
            signatures_required = federation.signatures_required if signatures_required.nil?
            local_actor = string_or_nil(fed["local_actor"]?) || federation.local_actor
            local_key_id = string_or_nil(fed["local_key_id"]?) || federation.local_key_id
            local_private_key_path = string_or_nil(fed["local_private_key_path"]?) || federation.local_private_key_path
            federation = Cogni::Config::FederationSettings.new(
              adapter, sqlite_path, auto_subscribe, poll_interval, http_timeout, signatures_required.not_nil!, local_actor, local_key_id, local_private_key_path
            )
          end
        end

        ml = base.ml
        if ml_raw = tree["ml"]?
          if ml_tree = ml_raw.as?(Hash(String, RCL::Value))
            registry_adapter = string_or_nil(ml_tree["registry_adapter"]?) || string_or_nil(ml_tree["adapter"]?) || ml.registry_adapter
            file_root = string_or_nil(ml_tree["file_root"]?) || ml.file_root
            default_runtime_adapter = string_or_nil(ml_tree["default_runtime_adapter"]?) || ml.default_runtime_adapter
            backend_priority = parse_string_list_value(ml_tree["backend_priority"]?)
            backend_priority = ml.backend_priority if backend_priority.empty?
            ml = Cogni::Config::MLSettings.new(registry_adapter, file_root, default_runtime_adapter, backend_priority)
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
          ml: ml,
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
        parse_string_list_value(value)
      end

      private def self.parse_string_list_value(value : RCL::Value?) : Array(String)
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

      private def self.apply_credentials_env_overrides(value : RCL::Value?) : Nil
        return unless value
        hash = value.as?(Hash(String, RCL::Value))
        return unless hash

        flatten_credentials(hash).each do |key, val|
          next if key.empty? || val.empty?
          ENV[key] = val unless ENV.has_key?(key)
        end
      end

      private def self.flatten_credentials(hash : Hash(String, RCL::Value), prefix : String = "") : Hash(String, String)
        out = {} of String => String
        hash.each do |key, value|
          normalized = normalize_env_key(key)
          full_key = prefix.empty? ? normalized : "#{prefix}_#{normalized}"

          case value
          when Hash(String, RCL::Value)
            nested = flatten_credentials(value, full_key)
            nested.each { |nk, nv| out[nk] = nv }
          when String
            out[full_key] = value
          when Bool
            out[full_key] = value ? "true" : "false"
          when Int32
            out[full_key] = value.to_s
          when Int64
            out[full_key] = value.to_s
          when Float64
            out[full_key] = value.to_s
          when Array(RCL::Value)
            strings = value.compact_map { |entry| entry.is_a?(String) ? entry : nil }
            out[full_key] = strings.join(" ") unless strings.empty?
          else
            next
          end
        end
        out
      end

      private def self.normalize_env_key(key : String) : String
        key.upcase.gsub(/[^A-Z0-9]+/, "_").gsub(/^_+|_+$/, "")
      end
    end
  end
end
