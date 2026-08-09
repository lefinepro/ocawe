require "set"

module OcaweCore
  module Utils
    module ConfigParser
      private def self.apply_raw_settings(base : Ocawe::Config::Settings, tree : Hash(String, RCL::Value)) : Ocawe::Config::Settings
        apply_credentials_env_overrides(tree["credentials"]?)

        workflows = base.workflows
        if wf_raw = tree["workflows"]?
          if wf = wf_raw.as?(Hash(String, RCL::Value))
            preferred = string_or_nil(wf["preferred_workflows_root"]?) || workflows.preferred_workflows_root
            workflows = Ocawe::Config::WorkflowSettings.new(preferred)
          end
        end

        datasets = base.datasets
        if ds_raw = tree["datasets"]?
          if ds = ds_raw.as?(Hash(String, RCL::Value))
            adapter = string_or_nil(ds["adapter"]?) || datasets.adapter
            file_root = string_or_nil(ds["file_root"]?) || datasets.file_root
            datasets = Ocawe::Config::DatasetSettings.new(adapter, file_root)
          end
        end

        scheduler = base.scheduler
        if scheduler_raw = tree["scheduler"]?
          if scheduler_config = scheduler_raw.as?(Hash(String, RCL::Value))
            enabled = bool_or_nil(scheduler_config["enabled"]?)
            scheduler = Ocawe::Config::SchedulerSettings.new(
              enabled: enabled.nil? ? scheduler.enabled : enabled.not_nil!,
              min_workers: int32_or_nil(scheduler_config["min_workers"]?) || scheduler.min_workers,
              max_workers: int32_or_nil(scheduler_config["max_workers"]?) || scheduler.max_workers,
              target_queue_depth: int32_or_nil(scheduler_config["target_queue_depth"]?) || scheduler.target_queue_depth,
              scale_up_cooldown_ms: int32_or_nil(scheduler_config["scale_up_cooldown_ms"]?) || scheduler.scale_up_cooldown_ms,
              scale_down_cooldown_ms: int32_or_nil(scheduler_config["scale_down_cooldown_ms"]?) || scheduler.scale_down_cooldown_ms,
            )
          elsif enabled = bool_or_nil(scheduler_raw)
            scheduler = Ocawe::Config::SchedulerSettings.new(
              enabled: enabled,
              min_workers: scheduler.min_workers,
              max_workers: scheduler.max_workers,
              target_queue_depth: scheduler.target_queue_depth,
              scale_up_cooldown_ms: scheduler.scale_up_cooldown_ms,
              scale_down_cooldown_ms: scheduler.scale_down_cooldown_ms,
            )
          end
        end

        webhooks = base.webhooks
        if webhooks_raw = tree["webhooks"]?
          if webhook_config = webhooks_raw.as?(Hash(String, RCL::Value))
            enabled = bool_or_nil(webhook_config["enabled"]?)
            default_workflow = string_or_nil(webhook_config["default_workflow"]?) || string_or_nil(webhook_config["defaultWorkflow"]?) || webhooks.default_workflow
            allowed_repos = parse_string_list_value(webhook_config["allowed_repos"]?)
            allowed_refs = parse_string_list_value(webhook_config["allowed_refs"]?)
            webhooks = Ocawe::Config::WebhookSettings.new(
              enabled: enabled.nil? ? webhooks.enabled : enabled.not_nil!,
              secret_env: string_or_nil(webhook_config["secret_env"]?) || string_or_nil(webhook_config["secretEnv"]?) || webhooks.secret_env,
              workspace_root: string_or_nil(webhook_config["workspace_root"]?) || string_or_nil(webhook_config["workspaceRoot"]?) || webhooks.workspace_root,
              default_workflow: default_workflow,
              allowed_repos: allowed_repos.empty? ? webhooks.allowed_repos : allowed_repos,
              allowed_refs: allowed_refs.empty? ? webhooks.allowed_refs : allowed_refs,
            )
          elsif enabled = bool_or_nil(webhooks_raw)
            webhooks = Ocawe::Config::WebhookSettings.new(
              enabled: enabled,
              secret_env: webhooks.secret_env,
              workspace_root: webhooks.workspace_root,
              default_workflow: webhooks.default_workflow,
              allowed_repos: webhooks.allowed_repos,
              allowed_refs: webhooks.allowed_refs,
            )
          end
        end

        federation = base.federation
        if fed_raw = tree["federation"]?
          if fed = fed_raw.as?(Hash(String, RCL::Value))
            auto_subscribe = parse_string_list_value(fed["auto_subscribe"]?)
            auto_subscribe = federation.auto_subscribe if auto_subscribe.empty?
            poll_interval = int32_or_nil(fed["s2s_poll_interval_seconds"]?) || federation.s2s_poll_interval_seconds
            http_timeout = int32_or_nil(fed["s2s_http_timeout_seconds"]?) || federation.s2s_http_timeout_seconds
            signatures_required = bool_or_nil(fed["signatures_required"]?)
            signatures_required = federation.signatures_required if signatures_required.nil?
            local_actor = string_or_nil(fed["local_actor"]?) || federation.local_actor
            local_key_id = string_or_nil(fed["local_key_id"]?) || federation.local_key_id
            local_private_key_path = string_or_nil(fed["local_private_key_path"]?) || federation.local_private_key_path
            actor_type = string_or_nil(fed["actor_type"]?) || federation.actor_type
            internal_origins = parse_header_map(fed["internal_origins"]?) || federation.internal_origins
            allow_private_address = bool_or_nil(fed["allow_private_address"]?)
            allow_private_address = federation.allow_private_address if allow_private_address.nil?
            internal_domain = string_or_nil(fed["internal_domain"]?) || federation.internal_domain
            internal_peers = Ocawe::Federation::InternalDomain.parse_peers(parse_string_list_value(fed["internal_peers"]?))
            internal_peers = federation.internal_peers if internal_peers.empty?
            federation = Ocawe::Config::FederationSettings.new(
              auto_subscribe: auto_subscribe,
              s2s_poll_interval_seconds: poll_interval,
              s2s_http_timeout_seconds: http_timeout,
              signatures_required: signatures_required.not_nil!,
              local_actor: local_actor,
              local_key_id: local_key_id,
              local_private_key_path: local_private_key_path,
              actor_type: actor_type,
              internal_origins: internal_origins,
              allow_private_address: allow_private_address.not_nil!,
              internal_domain: internal_domain,
              internal_peers: internal_peers,
            )
          end
        end

        api = base.api
        if api_raw = tree["api"]?
          parsed_api = parse_api_value(api_raw)
          api = Ocawe::Config::ApiSettings.new(parsed_api) unless parsed_api.empty?
        end

        functions = base.functions
        if fn_raw = tree["functions"]?
          if fn = fn_raw.as?(Hash(String, RCL::Value))
            enabled = parse_functions_value(fn["enabled"]?)
            unless enabled.empty?
              available = Ocawe::Config::DefaultFunctionHandlers.available
              resolved = {} of String => Ocawe::Workflow::FunctionHandler
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

        log_settings = base.log_settings
        if log_raw = tree["log"]?
          if log = log_raw.as?(Hash(String, RCL::Value))
            level_str = string_or_nil(log["level"]?)
            log_settings = Ocawe::Config::LogSettings.new(Ocawe::Config::LogLevel.parse(level_str)) if level_str
          elsif (level_str = string_or_nil(log_raw))
            log_settings = Ocawe::Config::LogSettings.new(Ocawe::Config::LogLevel.parse(level_str))
          end
        end

        telemetry = base.telemetry
        telemetry_raw = tree["telemetry"]? || tree["otel"]?
        if tel = telemetry_raw.try(&.as?(Hash(String, RCL::Value)))
          enabled = bool_or_nil(tel["enabled"]?)
          service_name = string_or_nil(tel["service_name"]?) || string_or_nil(tel["serviceName"]?) || telemetry.service_name
          service_version = string_or_nil(tel["service_version"]?) || string_or_nil(tel["serviceVersion"]?) || telemetry.service_version
          endpoint = string_or_nil(tel["endpoint"]?) || telemetry.endpoint
          headers = parse_header_map(tel["headers"]?) || telemetry.headers
          traces_enabled = bool_or_nil(tel["traces_enabled"]?) || bool_or_nil(tel["tracesEnabled"]?)
          metrics_enabled = bool_or_nil(tel["metrics_enabled"]?) || bool_or_nil(tel["metricsEnabled"]?)
          logs_enabled = bool_or_nil(tel["logs_enabled"]?) || bool_or_nil(tel["logsEnabled"]?)
          exporter = string_or_nil(tel["exporter"]?) || telemetry.exporter
          sample_ratio = float64_or_nil(tel["sample_ratio"]?) || float64_or_nil(tel["sampleRatio"]?) || telemetry.sample_ratio
          telemetry = Ocawe::Config::TelemetrySettings.new(
            enabled: enabled.nil? ? telemetry.enabled : enabled.not_nil!,
            service_name: service_name,
            service_version: service_version,
            endpoint: endpoint,
            headers: headers,
            traces_enabled: traces_enabled.nil? ? telemetry.traces_enabled : traces_enabled.not_nil!,
            metrics_enabled: metrics_enabled.nil? ? telemetry.metrics_enabled : metrics_enabled.not_nil!,
            logs_enabled: logs_enabled.nil? ? telemetry.logs_enabled : logs_enabled.not_nil!,
            exporter: exporter,
            sample_ratio: sample_ratio,
          )
        elsif enabled = bool_or_nil(telemetry_raw)
          telemetry = Ocawe::Config::TelemetrySettings.new(
            enabled: enabled,
            service_name: telemetry.service_name,
            service_version: telemetry.service_version,
            endpoint: telemetry.endpoint,
            headers: telemetry.headers,
            traces_enabled: telemetry.traces_enabled,
            metrics_enabled: telemetry.metrics_enabled,
            logs_enabled: telemetry.logs_enabled,
            exporter: telemetry.exporter,
            sample_ratio: telemetry.sample_ratio,
          )
        end

        Ocawe::Config::Settings.new(
          workflows: workflows,
          node_kinds: base.node_kinds,
          datasets: datasets,
          federation: federation,
          api: api,
          scheduler: scheduler,
          webhooks: webhooks,
          functions: functions,
          workspace_bootstrap: base.workspace_bootstrap,
          mcp: base.mcp,
          log_settings: log_settings,
          telemetry: telemetry,
        )
      end

      private def self.apply_rcl_settings(base : Ocawe::Config::Settings, raw : Hash(String, RCL::Value)) : Ocawe::Config::Settings
        root = raw["root"]?
        tree = root.is_a?(Hash(String, RCL::Value)) ? root : raw
        apply_raw_settings(base, tree)
      end

      # Applies settings from a root Cawfile bundle (no workflow context).
      def self.apply_cawfile_settings(base : Ocawe::Config::Settings, bundle : ACD::Discovery::CawfileBundle) : Ocawe::Config::Settings
        tree = {} of String => RCL::Value
        tree["federation"] = bundle.config_federation unless bundle.config_federation.empty?
        tree["datasets"] = bundle.config_datasets unless bundle.config_datasets.empty?
        tree["workflows"] = bundle.config_workflows unless bundle.config_workflows.empty?
        tree["node_kinds"] = bundle.config_node_kinds unless bundle.config_node_kinds.empty?
        tree["functions"] = bundle.config_functions unless bundle.config_functions.empty?
        tree["mcp"] = bundle.config_mcp unless bundle.config_mcp.empty?
        tree["log"] = bundle.config_log unless bundle.config_log.empty?
        tree["telemetry"] = bundle.config_telemetry unless bundle.config_telemetry.empty?
        tree["scheduler"] = bundle.config_scheduler unless bundle.config_scheduler.empty?
        tree["webhooks"] = bundle.config_webhooks unless bundle.config_webhooks.empty?

        # `follow [...]` in the workflow body is a subscription declaration: the
        # runtime follows those actors at startup, so it feeds `auto_subscribe`
        # directly. That makes `follow` alone enough to federate - no separate
        # `federation.auto_subscribe` line is required.
        unless bundle.follow.empty?
          fed = tree["federation"]?.as?(Hash(String, RCL::Value)) || ({} of String => RCL::Value)
          declared = parse_string_list_value(fed["auto_subscribe"]?)
          merged = (declared + bundle.follow).map(&.strip).reject(&.empty?).uniq!
          fed["auto_subscribe"] = merged.map(&.as(RCL::Value))
          tree["federation"] = fed
        end

        # `Api::Federation::Inbox` / `Api::Federation::Outbox` on a workflow's
        # types is the only declaration that enables federation - there is no
        # `api = [...]` setting to repeat it.
        if bundle.enable_federation
          api_value = tree["api"]?
          if api_value.is_a?(Hash(String, RCL::Value))
            # Already has api config - merge federation in
            existing = api_value
            unless existing.has_key?("federation")
              existing["enabled"] = ["classic", "federation"] of RCL::Value
            end
          else
            tree["api"] = {"enabled" => ["classic", "federation"] of RCL::Value} of String => RCL::Value
          end
        end

        apply_raw_settings(base, tree)
      end

      # Derives the local ActivityPub identity from the Cawfile's `#+name:`
      # header, so a bundle does not have to repeat its own host and port in
      # `federation.local_actor` / `federation.local_key_id`. The port is only
      # known after the CLI has parsed `--port`, which is why this is a separate
      # step from `apply_cawfile_settings`.
      #
      # An explicitly declared `local_actor` always wins - deployments that were
      # written before `#+name:` keep working unchanged.
      def self.apply_federation_identity(
        base : Ocawe::Config::Settings,
        bundle : ACD::Discovery::CawfileBundle,
        port : Int32,
      ) : Ocawe::Config::Settings
        name = bundle.name
        return base unless name && !name.strip.empty?
        return base if bundle.config_federation.has_key?("local_actor")

        federation = base.federation
        identifier = Ocawe::Federation::InternalDomain.slug(name)
        peers = federation.resolved_internal_peers
        # A peer map entry for this runtime's own name pins the origin peers will
        # dereference; without one, loopback is the only origin known to be
        # correct for a locally started runtime.
        origin = peers[identifier]? || "http://127.0.0.1:#{port}"
        local_actor = "#{origin.rstrip('/')}/actors/#{identifier}"
        local_key_id = bundle.config_federation.has_key?("local_key_id") ? federation.local_key_id : "#{local_actor}#main-key"

        Ocawe::Config::Settings.new(
          workflows: base.workflows,
          node_kinds: base.node_kinds,
          datasets: base.datasets,
          federation: Ocawe::Config::FederationSettings.new(
            auto_subscribe: federation.auto_subscribe,
            s2s_poll_interval_seconds: federation.s2s_poll_interval_seconds,
            s2s_http_timeout_seconds: federation.s2s_http_timeout_seconds,
            signatures_required: federation.signatures_required,
            local_actor: local_actor,
            local_key_id: local_key_id,
            local_private_key_path: federation.local_private_key_path,
            actor_type: federation.actor_type,
            internal_origins: federation.internal_origins,
            allow_private_address: federation.allow_private_address,
            internal_domain: federation.internal_domain,
            internal_peers: federation.internal_peers,
          ),
          api: base.api,
          scheduler: base.scheduler,
          webhooks: base.webhooks,
          functions: base.functions,
          workspace_bootstrap: base.workspace_bootstrap,
          mcp: base.mcp,
          log_settings: base.log_settings,
          telemetry: base.telemetry,
        )
      end

      private def self.document_to_h(doc : RCL::Document) : Hash(String, RCL::Value)
        if root = doc.root_value
          return {"root" => rcl_node_to_value(root)} of String => RCL::Value
        end

        result = {} of String => RCL::Value
        doc.blocks.each do |block|
          if arg = block.argument
            result[rcl_named_base(block.name)] = {arg => rcl_block_to_h(block)} of String => RCL::Value
          else
            result[block.name] = rcl_block_to_h(block)
          end
        end
        result
      end

      private def self.rcl_block_to_h(block : RCL::BlockNode) : Hash(String, RCL::Value)
        result = {} of String => RCL::Value

        block.properties.each do |key, node|
          insert_rcl_key_path!(result, key, rcl_node_to_value(node))
        end

        rcl_child_blocks(block).each do |child|
          child_h = rcl_block_to_h(child)
          if arg = child.argument
            base = rcl_named_base(child.name)
            branch = result[base]?.as?(Hash(String, RCL::Value)) || ({} of String => RCL::Value)
            branch[arg] = child_h
            result[base] = branch
          elsif existing = result[child.name]?.as?(Hash(String, RCL::Value))
            merged = child_h.dup
            existing.each { |key, value| merged[key] = value }
            result[child.name] = merged
          else
            result[child.name] = child_h
          end
        end

        result
      end

      private def self.rcl_child_blocks(block : RCL::BlockNode) : Array(RCL::BlockNode)
        seen = Set(UInt64).new
        out = [] of RCL::BlockNode
        block.blocks.each_value do |child|
          oid = child.object_id
          next if seen.includes?(oid)
          seen << oid
          out << child
        end
        block.named_blocks.each do |child|
          oid = child.object_id
          next if seen.includes?(oid)
          seen << oid
          out << child
        end
        out
      end

      private def self.rcl_node_to_value(node : RCL::ASTNode) : RCL::Value
        case node
        when RCL::StringNode
          node.value
        when RCL::NumberNode
          node.value
        when RCL::BooleanNode
          node.value
        when RCL::ArrayNode
          values = [] of RCL::Value
          node.elements.each { |entry| values << rcl_node_to_value(entry) }
          values
        when RCL::BlockNode
          rcl_block_to_h(node)
        else
          ""
        end
      end

      private def self.insert_rcl_key_path!(target : Hash(String, RCL::Value), key : String, value : RCL::Value) : Nil
        parts = key.split('.')
        if parts.size == 1
          raise "Duplicate key '#{key}'" if target.has_key?(key)
          target[key] = value
          return
        end

        head = parts[0]
        existing = target[head]?
        raise "Key conflict at '#{head}'" if existing && !existing.is_a?(Hash(String, RCL::Value))

        branch = existing.as?(Hash(String, RCL::Value)) || ({} of String => RCL::Value)
        insert_rcl_key_path!(branch, parts[1, parts.size - 1].join("."), value)
        target[head] = branch
      end

      private def self.rcl_named_base(name : String) : String
        name == "region" ? "regions" : name
      end

      def self.string_or_nil(value : RCL::Value?) : String?
        value.is_a?(String) ? value : nil
      end

      def self.int32_or_nil(value : RCL::Value?) : Int32?
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

      private def self.float64_or_nil(value : RCL::Value?) : Float64?
        case value
        when Float64
          value
        when Float32
          value.to_f64
        when Int32
          value.to_f64
        when Int64
          value.to_f64
        when String
          value.to_f64?
        else
          nil
        end
      end

      private def self.parse_header_map(value : RCL::Value?) : Hash(String, String)?
        if raw = value.as?(Hash(String, RCL::Value))
          headers = {} of String => String
          raw.each do |key, header_value|
            if str = string_or_nil(header_value)
              headers[key] = str
            end
          end
          return headers
        end

        if raw = string_or_nil(value)
          headers = {} of String => String
          raw.split(",").each do |entry|
            key, val = parse_assignment(entry)
            headers[key] = val if key && !key.empty?
          end
          return headers
        end

        nil
      end

      private def self.parse_api_value(value : RCL::Value) : Array(String)
        case value
        when String
          [value]
        when Array
          value.compact_map { |entry| entry.is_a?(String) ? entry : nil }
        when Hash(String, RCL::Value)
          nested = value["enabled"]? || value["value"]?
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
