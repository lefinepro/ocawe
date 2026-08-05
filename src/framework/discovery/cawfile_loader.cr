require "rcl"
require "set"

module ACD
  module Discovery
    enum ContainerMode
      Static
      Nix
    end

    struct CawfileContainer
      getter mode : ContainerMode
      getter packages : Array(String)
      getter image : String?
      # Explicit list of files to copy into the container build context.
      # Empty means "resolve at build time" (copy all directory files).
      getter files : Array(String)

      def initialize(
        @mode : ContainerMode = ContainerMode::Static,
        @packages : Array(String) = [] of String,
        @image : String? = nil,
        @files : Array(String) = [] of String,
      )
      end
    end

    struct CrystalLoader
      getter code : Array(String)
      getter requires : Array(String)
      property registry_files : Array(String)

      def initialize(
        @code : Array(String) = [] of String,
        @requires : Array(String) = [] of String,
        @registry_files : Array(String) = [] of String,
      )
      end
    end

    struct CawfileResource
      getter id : String
      getter name : String
      getter description : String
      getter action : String
      getter purpose : String
      getter tags : Array(String)

      def initialize(
        @id : String,
        @name : String = "",
        @description : String = "",
        @action : String = "deliverService",
        @purpose : String = "request",
        @tags : Array(String) = [] of String,
      )
      end
    end

    struct CawfileTestAssertion
      getter workflow_id : String
      getter input : String
      getter equality : String
      getter wait_seconds : Int32

      def initialize(
        @workflow_id : String,
        @input : String = "",
        @equality : String = "",
        @wait_seconds : Int32 = 0,
      )
      end
    end

    struct CawfileTest
      getter name : String
      getter assertions : Array(CawfileTestAssertion)

      def initialize(@name : String, @assertions : Array(CawfileTestAssertion) = [] of CawfileTestAssertion)
      end
    end

    struct CawfileTriggers
      include JSON::Serializable

      getter status : String
      getter schedule : String?
      getter trigger_message : String?
      getter tags : Array(String)

      def initialize(
        @schedule : String? = nil,
        @trigger_message : String? = nil,
        @tags : Array(String) = [] of String,
      )
        @status = configured? ? "configured" : "not_configured"
      end

      def configured? : Bool
        !@schedule.nil? || !@trigger_message.nil? || !@tags.empty?
      end
    end

    struct CawfileBundle
      getter id : String
      # Embedded config (mirrors ocawe.config.rcl fields)
      getter config_federation : Hash(String, RCL::Value)
      getter config_datasets : Hash(String, RCL::Value)
      getter config_workflows : Hash(String, RCL::Value)
      getter config_node_kinds : Hash(String, RCL::Value)
      getter config_functions : Hash(String, RCL::Value)
      getter config_mcp : Hash(String, RCL::Value)
      getter config_log : Hash(String, RCL::Value)
      getter config_telemetry : Hash(String, RCL::Value)
      getter config_scheduler : Hash(String, RCL::Value)
      getter config_webhooks : Hash(String, RCL::Value)
      getter start_settings : Hash(String, RCL::Value)
      # Raw .acd.cr-style DSL source lines inside the workflow block
      getter dsl_source : Array(String)?
      # Federation follow targets extracted from workflow block
      getter follow : Array(String)
      # ActivityPub resources this workflow actor publishes
      getter resources : Array(CawfileResource)
      # Cawfile-level workflow tests.
      getter tests : Array(CawfileTest)
      # Declarative trigger metadata. Ocawe stores and exposes this metadata but
      # does not execute schedules or message matches itself.
      getter triggers : CawfileTriggers
      # Container configuration (static or nix with packages)
      getter container : CawfileContainer?
      # Whether federation API should be enabled (detected from Api::Federation usage)
      getter enable_federation : Bool
      # Whether models API should be enabled (detected from Api::Models usage)
      getter enable_models : Bool
      # Workflow input/output type names extracted from @[Validate(...)]
      getter input_type : String?
      getter output_type : String?
      # Default model extracted from @[Model(...)]
      getter model : String?
      # Default name extracted from #+name: header
      getter name : String?
      # Whether this workflow should start when the HTTP runtime starts.
      getter service : Bool
      # Crystal code extracted from Cawfile (requires, structs, etc.)
      getter crystal_loader : CrystalLoader?

      def initialize(
        @id : String,
        @config_federation : Hash(String, RCL::Value) = {} of String => RCL::Value,
        @config_datasets : Hash(String, RCL::Value) = {} of String => RCL::Value,
        @config_workflows : Hash(String, RCL::Value) = {} of String => RCL::Value,
        @config_node_kinds : Hash(String, RCL::Value) = {} of String => RCL::Value,
        @config_functions : Hash(String, RCL::Value) = {} of String => RCL::Value,
        @config_mcp : Hash(String, RCL::Value) = {} of String => RCL::Value,
        @config_log : Hash(String, RCL::Value) = {} of String => RCL::Value,
        @config_telemetry : Hash(String, RCL::Value) = {} of String => RCL::Value,
        @config_scheduler : Hash(String, RCL::Value) = {} of String => RCL::Value,
        @config_webhooks : Hash(String, RCL::Value) = {} of String => RCL::Value,
        @start_settings : Hash(String, RCL::Value) = {} of String => RCL::Value,
        @dsl_source : Array(String)? = nil,
        @follow : Array(String) = [] of String,
        @resources : Array(CawfileResource) = [] of CawfileResource,
        @tests : Array(CawfileTest) = [] of CawfileTest,
        @triggers : CawfileTriggers = CawfileTriggers.new,
        @container : CawfileContainer? = nil,
        @enable_federation : Bool = false,
        @enable_models : Bool = false,
        @input_type : String? = nil,
        @output_type : String? = nil,
        @model : String? = nil,
        @crystal_loader : CrystalLoader? = nil,
        @name : String? = nil,
        @service : Bool = false,
      )
      end
    end

    private struct WorkflowBlockSlice
      getter id : String
      getter annotations : Array(String)
      getter dsl_source : Array(String)

      def initialize(@id : String, @annotations : Array(String), @dsl_source : Array(String))
      end
    end

    class CawfileLoader
      CAWFILE_NAMES = ["Cawfile", ".caw"]

      def self.find_cawfile(dir : String) : String?
        CAWFILE_NAMES.each do |name|
          path = File.join(dir, name)
          return path if File.file?(path)
        end
        nil
      end

      def self.load(dir : String, id : String) : CawfileBundle?
        bundles = load_all(dir)
        return nil if bundles.empty?

        bundles.find { |bundle| bundle.id == id } || bundles.first?
      end

      def self.load_all(dir : String) : Array(CawfileBundle)
        path = find_cawfile(dir)
        return [] of CawfileBundle unless path

        raw_content = normalize_raw_content(File.read(path))
        raw_lines = raw_content.lines
        workflow_slices = extract_workflow_block_slices(raw_lines)
        return [] of CawfileBundle if workflow_slices.empty?

        root_config = parse_root_config(raw_content, raw_lines)
        container = extract_container_from_raw(raw_lines)
        enable_federation = detect_federation_from_raw(raw_lines)
        enable_models = detect_models_from_raw(raw_lines)
        name = extract_name_from_raw(raw_lines)
        resources = extract_comment_resources(raw_lines, name)
        tests = extract_test_blocks(raw_lines)
        triggers = extract_triggers(raw_lines)

        crystal = extract_crystal_code(raw_lines)
        crystal.registry_files = discover_registry_files(crystal.requires, dir)

        workflow_slices.map do |slice|
          model, input_type, output_type = extract_model_and_validate(slice.annotations, path, dir)
          CawfileBundle.new(
            id: slice.id,
            dsl_source: slice.dsl_source,
            config_federation: root_config.config_federation,
            config_datasets: root_config.config_datasets,
            config_workflows: root_config.config_workflows,
            config_node_kinds: root_config.config_node_kinds,
            config_functions: root_config.config_functions,
            config_mcp: root_config.config_mcp,
            config_log: root_config.config_log,
            config_telemetry: root_config.config_telemetry,
            config_scheduler: root_config.config_scheduler,
            config_webhooks: root_config.config_webhooks,
            start_settings: root_config.start_settings,
            follow: extract_follow_from_raw(slice.dsl_source),
            resources: resources,
            tests: tests,
            triggers: triggers,
            container: container,
            enable_federation: enable_federation,
            enable_models: enable_models,
            input_type: input_type,
            output_type: output_type,
            model: model,
            crystal_loader: crystal,
            name: name,
            service: service_annotation?(slice.annotations),
          )
        end
      end

      def self.load_legacy(dir : String, id : String) : CawfileBundle?
        path = find_cawfile(dir)
        return nil unless path

        raw_content = normalize_raw_content(File.read(path))
        raw_lines = raw_content.lines
        triggers = extract_triggers(raw_lines)

        # First, try to parse with RCL to extract settings, import, and follow
        begin
          doc = RCL.parse_string(raw_content)
          workflow_block = find_workflow_block(doc)

          if workflow_block
            workflow_id = workflow_block.argument || id
            root_config = parse_settings_block(doc)
            follow = extract_follow(workflow_block)
            container = extract_container_from_raw(raw_lines)
            dsl_lines = extract_workflow_body_lines(raw_lines)

            enable_federation = detect_federation_from_raw(raw_lines)
            enable_models = detect_models_from_raw(raw_lines)
            model, input_type, output_type = extract_model_and_validate(raw_lines, dir, dir)
            name = extract_name_from_raw(raw_lines)
            resources = extract_comment_resources(raw_lines, name)
            tests = extract_test_blocks(raw_lines)

            crystal = extract_crystal_code(raw_lines)
            crystal.registry_files = discover_registry_files(crystal.requires, dir)

            return CawfileBundle.new(
              id: workflow_id,
              dsl_source: dsl_lines,
              config_federation: root_config.config_federation,
              config_datasets: root_config.config_datasets,
              config_workflows: root_config.config_workflows,
              config_node_kinds: root_config.config_node_kinds,
              config_functions: root_config.config_functions,
              config_mcp: root_config.config_mcp,
              config_log: root_config.config_log,
              config_telemetry: root_config.config_telemetry,
              config_scheduler: root_config.config_scheduler,
              config_webhooks: root_config.config_webhooks,
              start_settings: root_config.start_settings,
              follow: follow,
              resources: resources,
              tests: tests,
              triggers: triggers,
              container: container,
              enable_federation: enable_federation,
              enable_models: enable_models,
              input_type: input_type,
              output_type: output_type,
              model: model,
              crystal_loader: crystal,
              name: name
            )
          end

          # No workflow block: just parse settings
          return nil
        rescue ex
          # RCL parse failed - fall back to raw line-based parsing
          follow = extract_follow_from_raw(raw_lines)
          container = extract_container_from_raw(raw_lines)
          enable_federation = detect_federation_from_raw(raw_lines)
          enable_models = detect_models_from_raw(raw_lines)
          dsl_lines = extract_workflow_body_lines(raw_lines)

          # Extract settings from raw lines
          fed = {} of String => RCL::Value
          ds = {} of String => RCL::Value
          wf = {} of String => RCL::Value
          nk = {} of String => RCL::Value
          fn = {} of String => RCL::Value
          mcp = {} of String => RCL::Value
          telemetry = {} of String => RCL::Value
          scheduler = {} of String => RCL::Value
          webhooks = {} of String => RCL::Value
          start = {} of String => RCL::Value

          in_settings = false
          settings_depth = 0
          raw_lines.each do |line|
            stripped = line.strip
            if stripped.match(/^\s*settings\s+do/)
              in_settings = true
              settings_depth = 1
              next
            end
            if in_settings
              if stripped.match(/^do/)
                settings_depth += 1
                next
              end
              if stripped.match(/^end/)
                settings_depth -= 1
                if settings_depth <= 0
                  in_settings = false
                  next
                end
              end
              # Parse dot-notation keys
              if eq_idx = stripped.index('=')
                key = stripped[0, eq_idx].strip
                value_raw = stripped[eq_idx + 1, stripped.size - eq_idx - 1].strip
                case key
                when "port"
                  start["port"] = parse_value(value_raw)
                when "log_level"
                  start["log_level"] = parse_value(value_raw)
                when "webhooks"
                  webhooks["enabled"] = parse_value(value_raw)
                else
                  if key.includes?('.')
                    parts = key.split('.', 2)
                    block_name = parts[0]
                    prop_name = parts[1]
                    case block_name
                    when "federation"
                      fed[prop_name] = parse_value(value_raw)
                    when "data", "datasets"
                      ds[prop_name] = parse_value(value_raw)
                    when "workflows"
                      wf[prop_name] = parse_value(value_raw)
                    when "telemetry", "otel"
                      telemetry[prop_name] = parse_value(value_raw)
                    when "scheduler"
                      scheduler[prop_name] = parse_value(value_raw)
                    when "webhooks"
                      webhooks[prop_name] = parse_value(value_raw)
                    end
                  end
                end
              end
            end
          end

          scheduler.merge!(extract_raw_settings_child_block(raw_lines, "scheduler"))
          webhooks.merge!(extract_raw_settings_child_block(raw_lines, "webhooks"))

          workflow_id = "root"
          if wf_block_line = raw_lines.find { |l| l.match(/^\s*workflow\s+"/) }
            workflow_id = wf_block_line.match(/^\s*workflow\s+"([^"]+)"/).try { |m| m[1] } || "root"
          end

          model, input_type, output_type = extract_model_and_validate(raw_lines, path, dir)
          name = extract_name_from_raw(raw_lines)
          resources = extract_comment_resources(raw_lines, name)
          tests = extract_test_blocks(raw_lines)

          crystal = extract_crystal_code(raw_lines)
          crystal.registry_files = discover_registry_files(crystal.requires, dir)

          CawfileBundle.new(
            id: workflow_id,
            dsl_source: dsl_lines,
            config_federation: fed,
            config_datasets: ds,
            config_workflows: wf,
            config_node_kinds: nk,
            config_functions: fn,
            config_mcp: mcp,
            config_log: {} of String => RCL::Value,
            config_telemetry: telemetry,
            config_scheduler: scheduler,
            config_webhooks: webhooks,
            start_settings: start,
            follow: follow,
            resources: resources,
            tests: tests,
            triggers: triggers,
            container: container,
            enable_federation: enable_federation,
            enable_models: enable_models,
            input_type: input_type,
            output_type: output_type,
            model: model,
            crystal_loader: crystal,
            name: name
          )
        end
      end

      def self.load_root(dir : String = Dir.current) : CawfileBundle?
        path = find_cawfile(dir)
        return nil unless path

        raw_content = normalize_raw_content(File.read(path))
        raw_lines = raw_content.lines
        triggers = extract_triggers(raw_lines)

        begin
          doc = RCL.parse_string(raw_content)
          workflow_block = find_workflow_block(doc)

          if workflow_block
            root_config = parse_settings_block(doc)
            dsl_lines = extract_workflow_body_lines(raw_lines)
            follow = extract_follow(workflow_block)
            container = extract_container_from_raw(raw_lines)
            name = extract_name_from_raw(raw_lines)
            resources = extract_comment_resources(raw_lines, name)
            tests = extract_test_blocks(raw_lines)

            crystal = extract_crystal_code(raw_lines)
            crystal.registry_files = discover_registry_files(crystal.requires, dir)

            CawfileBundle.new(
              id: workflow_block.argument || "root",
              dsl_source: dsl_lines,
              config_federation: root_config.config_federation,
              config_datasets: root_config.config_datasets,
              config_workflows: root_config.config_workflows,
              config_node_kinds: root_config.config_node_kinds,
              config_functions: root_config.config_functions,
              config_mcp: root_config.config_mcp,
              config_log: root_config.config_log,
              config_telemetry: root_config.config_telemetry,
              config_scheduler: root_config.config_scheduler,
              config_webhooks: root_config.config_webhooks,
              start_settings: root_config.start_settings,
              follow: follow,
              resources: resources,
              tests: tests,
              triggers: triggers,
              container: container,
              enable_federation: detect_federation_from_raw(raw_lines),
              enable_models: detect_models_from_raw(raw_lines),
              crystal_loader: crystal,
              name: name
            )
          else
            parse_settings_block(doc)
          end
        rescue ex
          # RCL parse failed - fall back to raw line-based parsing
          follow = extract_follow_from_raw(raw_lines)
          container = extract_container_from_raw(raw_lines)
          dsl_lines = extract_workflow_body_lines(raw_lines)

          fed = {} of String => RCL::Value
          ds = {} of String => RCL::Value
          wf = {} of String => RCL::Value
          nk = {} of String => RCL::Value
          fn = {} of String => RCL::Value
          mcp = {} of String => RCL::Value
          telemetry = {} of String => RCL::Value
          scheduler = {} of String => RCL::Value
          webhooks = {} of String => RCL::Value
          start = {} of String => RCL::Value

          in_settings = false
          settings_depth = 0
          raw_lines.each do |line|
            stripped = line.strip
            if stripped.match(/^\s*settings\s+do/)
              in_settings = true
              settings_depth = 1
              next
            end
            if in_settings
              if stripped.match(/^do/)
                settings_depth += 1
                next
              end
              if stripped.match(/^end/)
                settings_depth -= 1
                if settings_depth <= 0
                  in_settings = false
                  next
                end
              end
              if eq_idx = stripped.index('=')
                key = stripped[0, eq_idx].strip
                value_raw = stripped[eq_idx + 1, stripped.size - eq_idx - 1].strip
                case key
                when "port"
                  start["port"] = parse_value(value_raw)
                when "log_level"
                  start["log_level"] = parse_value(value_raw)
                when "webhooks"
                  webhooks["enabled"] = parse_value(value_raw)
                else
                  if key.includes?('.')
                    parts = key.split('.', 2)
                    block_name = parts[0]
                    prop_name = parts[1]
                    case block_name
                    when "federation"
                      fed[prop_name] = parse_value(value_raw)
                    when "data", "datasets"
                      ds[prop_name] = parse_value(value_raw)
                    when "workflows"
                      wf[prop_name] = parse_value(value_raw)
                    when "telemetry", "otel"
                      telemetry[prop_name] = parse_value(value_raw)
                    when "scheduler"
                      scheduler[prop_name] = parse_value(value_raw)
                    when "webhooks"
                      webhooks[prop_name] = parse_value(value_raw)
                    end
                  end
                end
              end
            end
          end

          scheduler.merge!(extract_raw_settings_child_block(raw_lines, "scheduler"))
          webhooks.merge!(extract_raw_settings_child_block(raw_lines, "webhooks"))

          workflow_id = "root"
          if wf_block_line = raw_lines.find { |l| l.match(/^\s*workflow\s+"/) }
            workflow_id = wf_block_line.match(/^\s*workflow\s+"([^"]+)"/).try { |m| m[1] } || "root"
          end

          model, input_type, output_type = extract_model_and_validate(raw_lines, path, dir)
          name = extract_name_from_raw(raw_lines)
          resources = extract_comment_resources(raw_lines, name)
          tests = extract_test_blocks(raw_lines)

          crystal = extract_crystal_code(raw_lines)
          crystal.registry_files = discover_registry_files(crystal.requires, dir)

          CawfileBundle.new(
            id: workflow_id,
            dsl_source: dsl_lines,
            config_federation: fed,
            config_datasets: ds,
            config_workflows: wf,
            config_node_kinds: nk,
            config_functions: fn,
            config_mcp: mcp,
            config_log: {} of String => RCL::Value,
            config_telemetry: telemetry,
            config_scheduler: scheduler,
            config_webhooks: webhooks,
            start_settings: start,
            follow: follow,
            resources: resources,
            tests: tests,
            triggers: triggers,
            container: container,
            enable_federation: detect_federation_from_raw(raw_lines),
            enable_models: detect_models_from_raw(raw_lines),
            input_type: input_type,
            output_type: output_type,
            model: model,
            crystal_loader: crystal,
            name: name
          )
        end
      end

      private def self.normalize_raw_content(content : String) : String
        content.ends_with?('\n') ? content : "#{content}\n"
      end

      private def self.parse_root_config(raw_content : String, raw_lines : Array(String)) : CawfileBundle
        parse_settings_block(RCL.parse_string(raw_content))
      rescue
        parse_raw_settings(raw_lines)
      end

      private def self.parse_raw_settings(raw_lines : Array(String)) : CawfileBundle
        fed = {} of String => RCL::Value
        ds = {} of String => RCL::Value
        wf = {} of String => RCL::Value
        nk = {} of String => RCL::Value
        fn = {} of String => RCL::Value
        mcp = {} of String => RCL::Value
        telemetry = {} of String => RCL::Value
        scheduler = {} of String => RCL::Value
        webhooks = {} of String => RCL::Value
        start = {} of String => RCL::Value

        in_settings = false
        settings_depth = 0
        raw_lines.each do |line|
          stripped = line.strip
          if stripped.match(/^\s*settings\s+do/)
            in_settings = true
            settings_depth = 1
            next
          end
          if in_settings
            if stripped.match(/^do/)
              settings_depth += 1
              next
            end
            if stripped.match(/^end/)
              settings_depth -= 1
              if settings_depth <= 0
                in_settings = false
                next
              end
            end
            if eq_idx = stripped.index('=')
              key = stripped[0, eq_idx].strip
              value_raw = stripped[eq_idx + 1, stripped.size - eq_idx - 1].strip
              case key
              when "port"
                start["port"] = parse_value(value_raw)
              when "log_level"
                start["log_level"] = parse_value(value_raw)
              when "webhooks"
                webhooks["enabled"] = parse_value(value_raw)
              else
                if key.includes?('.')
                  parts = key.split('.', 2)
                  block_name = parts[0]
                  prop_name = parts[1]
                  case block_name
                  when "federation"
                    fed[prop_name] = parse_value(value_raw)
                  when "data", "datasets"
                    ds[prop_name] = parse_value(value_raw)
                  when "workflows"
                    wf[prop_name] = parse_value(value_raw)
                  when "telemetry", "otel"
                    telemetry[prop_name] = parse_value(value_raw)
                  when "scheduler"
                    scheduler[prop_name] = parse_value(value_raw)
                  when "webhooks"
                    webhooks[prop_name] = parse_value(value_raw)
                  end
                end
              end
            end
          end
        end

        scheduler.merge!(extract_raw_settings_child_block(raw_lines, "scheduler"))
        webhooks.merge!(extract_raw_settings_child_block(raw_lines, "webhooks"))

        CawfileBundle.new(
          id: "root",
          config_federation: fed,
          config_datasets: ds,
          config_workflows: wf,
          config_node_kinds: nk,
          config_functions: fn,
          config_mcp: mcp,
          config_telemetry: telemetry,
          config_scheduler: scheduler,
          config_webhooks: webhooks,
          start_settings: start,
          resources: [] of CawfileResource,
        )
      end

      # Parses settings block for federation, data, etc.
      # settings do
      #   federation.auto_subscribe = [...]
      #   data.adapter = "memory"
      #   port = 8080
      # end
      private def self.parse_settings_block(doc : RCL::Document) : CawfileBundle
        settings_block = doc.blocks.find { |b| b.name == "settings" }
        return CawfileBundle.new(id: "root") unless settings_block

        fed = {} of String => RCL::Value
        ds = {} of String => RCL::Value
        wf = {} of String => RCL::Value
        nk = {} of String => RCL::Value
        fn = {} of String => RCL::Value
        mcp = {} of String => RCL::Value
        log = {} of String => RCL::Value
        telemetry = {} of String => RCL::Value
        scheduler = {} of String => RCL::Value
        webhooks = {} of String => RCL::Value
        start = {} of String => RCL::Value

        # Parse properties in settings block
        settings_block.properties.each do |key, value|
          case key
          when "port"
            start["port"] = ast_node_to_value(value)
          when "log_level"
            start["log_level"] = ast_node_to_value(value)
          when "webhooks"
            webhooks["enabled"] = ast_node_to_value(value)
          else
            # Check for dot-notation keys like "data.adapter"
            if key.includes?('.')
              parts = key.split('.', 2)
              block_name = parts[0]
              prop_name = parts[1]
              case block_name
              when "federation"
                fed[prop_name] = ast_node_to_value(value)
              when "data", "datasets"
                ds[prop_name] = ast_node_to_value(value)
              when "workflows"
                wf[prop_name] = ast_node_to_value(value)
              when "telemetry", "otel"
                telemetry[prop_name] = ast_node_to_value(value)
              when "scheduler"
                scheduler[prop_name] = ast_node_to_value(value)
              when "webhooks"
                webhooks[prop_name] = ast_node_to_value(value)
              end
            end
          end
        end

        # Parse nested blocks in settings
        settings_child_blocks(settings_block).each do |child|
          case child.name
          when "federation"
            fed.merge!(block_to_rcl_value_h(child))
          when "datasets", "data"
            ds.merge!(block_to_rcl_value_h(child))
          when "workflows"
            wf.merge!(block_to_rcl_value_h(child))
          when "node_kinds"
            nk.merge!(block_to_rcl_value_h(child))
          when "functions"
            fn.merge!(block_to_rcl_value_h(child))
          when "mcp"
            mcp.merge!(block_to_rcl_value_h(child))
          when "log"
            log.merge!(block_to_rcl_value_h(child))
          when "telemetry", "otel"
            telemetry.merge!(block_to_rcl_value_h(child))
          when "scheduler"
            scheduler.merge!(block_to_rcl_value_h(child))
          when "webhooks"
            webhooks.merge!(block_to_rcl_value_h(child))
          end
        end

        CawfileBundle.new(
          id: "root",
          config_federation: fed,
          config_datasets: ds,
          config_workflows: wf,
          config_node_kinds: nk,
          config_functions: fn,
          config_mcp: mcp,
          config_log: log,
          config_telemetry: telemetry,
          config_scheduler: scheduler,
          config_webhooks: webhooks,
          start_settings: start,
          resources: [] of CawfileResource,
        )
      end

      private def self.extract_raw_settings_child_block(raw_lines : Array(String), block_name : String) : Hash(String, RCL::Value)
        result = {} of String => RCL::Value
        in_settings = false
        settings_depth = 0
        in_child = false
        child_depth = 0

        raw_lines.each do |line|
          stripped = line.strip
          next if stripped.empty? || stripped.starts_with?("#")

          unless in_settings
            if stripped.match(/^\s*settings\s+do\s*$/)
              in_settings = true
              settings_depth = 1
            end
            next
          end

          if in_child
            if stripped.match(/\bdo\s*$/)
              child_depth += 1
            elsif stripped == "end"
              child_depth -= 1
              if child_depth <= 0
                in_child = false
                next
              end
            end

            if eq_idx = stripped.index('=')
              key = stripped[0, eq_idx].strip
              value_raw = stripped[eq_idx + 1, stripped.size - eq_idx - 1].strip
              result[key] = parse_value(value_raw)
            end
            next
          end

          if stripped.match(/^#{Regex.escape(block_name)}\s+do\s*$/)
            in_child = true
            child_depth = 1
            next
          end

          if stripped.match(/\bdo\s*$/)
            settings_depth += 1
          elsif stripped == "end"
            settings_depth -= 1
            break if settings_depth <= 0
          end
        end

        result
      end

      private def self.find_workflow_block(doc : RCL::Document) : RCL::BlockNode?
        doc.blocks.each do |top_block|
          return top_block if top_block.name == "workflow"
        end
        nil
      end

      private def self.settings_child_blocks(block : RCL::BlockNode) : Array(RCL::BlockNode)
        seen = Set(UInt64).new
        children = [] of RCL::BlockNode
        block.blocks.each_value do |child|
          oid = child.object_id
          next if seen.includes?(oid)
          seen << oid
          children << child
        end
        block.named_blocks.each do |child|
          oid = child.object_id
          next if seen.includes?(oid)
          seen << oid
          children << child
        end
        children
      end

      private def self.normalize_resource_tags(tags : Array(String)) : Array(String)
        normalized = tags
          .map(&.strip)
          .reject(&.empty?)
          .map { |tag| tag.starts_with?('#') ? tag[1..] : tag }
        normalized.uniq!
        normalized
      end

      private def self.extract_follow(workflow_block : RCL::BlockNode) : Array(String)
        follow_node = workflow_block.properties["follow"]? || workflow_block["follow"]?
        return [] of String unless follow_node

        arr = follow_node.as?(RCL::ArrayNode)
        return [] of String unless arr

        arr.elements.compact_map { |e| e.is_a?(RCL::StringNode) ? e.value : nil }
      rescue
        [] of String
      end

      private def self.extract_workflow_body_lines(lines : Array(String)) : Array(String)?
        start_idx = nil
        lines.each_with_index do |line, idx|
          if line.match(/^\s*workflow\s+"[^"]+"\s+do\s*(?:#.*)?$/)
            start_idx = idx + 1
            break
          end
        end
        return nil unless start_idx

        depth = 1
        end_idx = start_idx
        (start_idx...lines.size).each do |idx|
          stripped = lines[idx].strip
          if stripped.match(/^\s*(workflow\s+"[^"]+"|settings|if\s+|unless\s+|while\s+|until\s+|parallel)\b.*\bdo\b/) ||
             stripped.match(/^\s*(if|unless)\s+/)
            depth += 1
          elsif stripped.match(/^\s*\bend\b/)
            depth -= 1
            if depth == 0
              end_idx = idx
              break
            end
          end
        end

        lines[start_idx...end_idx]
      end

      private def self.extract_workflow_block_slices(lines : Array(String)) : Array(WorkflowBlockSlice)
        slices = [] of WorkflowBlockSlice

        idx = 0
        while idx < lines.size
          line = lines[idx]
          match = line.match(/^\s*workflow\s+"([^"]+)"\s+do\s*(?:#.*)?$/)
          unless match
            idx += 1
            next
          end

          annotations = [] of String
          annotation_idx = idx - 1
          while annotation_idx >= 0
            stripped = lines[annotation_idx].strip
            if stripped.empty?
              annotation_idx -= 1
              next
            end
            break unless stripped.starts_with?("@[")
            annotations.unshift(stripped)
            annotation_idx -= 1
          end

          start_idx = idx + 1
          depth = 1
          end_idx = start_idx
          (start_idx...lines.size).each do |body_idx|
            stripped = lines[body_idx].strip
            if stripped.match(/^\s*(workflow\s+"[^"]+"|settings|if\s+|unless\s+|while\s+|until\s+|parallel|loop|dataset)\b.*\bdo\b/) ||
               stripped.match(/^\s*(if|unless)\s+/)
              depth += 1
            elsif stripped.match(/^\s*\bend\b/)
              depth -= 1
              if depth == 0
                end_idx = body_idx
                break
              end
            end
          end

          slices << WorkflowBlockSlice.new(match[1], annotations, lines[start_idx...end_idx])
          idx = end_idx + 1
        end

        slices
      end

      private def self.extract_test_blocks(lines : Array(String)) : Array(CawfileTest)
        tests = [] of CawfileTest

        idx = 0
        while idx < lines.size
          line = lines[idx]
          match = line.match(/^\s*test\s+"([^"]+)"\s+do\s*(?:#.*)?$/)
          unless match
            idx += 1
            next
          end

          start_idx = idx + 1
          depth = 1
          end_idx = start_idx
          (start_idx...lines.size).each do |body_idx|
            stripped = lines[body_idx].strip
            if stripped.match(/^\s*(test\s+"[^"]+"|workflow\s+"[^"]+"|settings|if\s+|unless\s+|while\s+|until\s+|parallel|loop|dataset)\b.*\bdo\b/) ||
               stripped.match(/^\s*(if|unless)\s+/)
              depth += 1
            elsif stripped.match(/^\s*\bend\b/)
              depth -= 1
              if depth == 0
                end_idx = body_idx
                break
              end
            end
          end

          assertions = lines[start_idx...end_idx]
            .compact_map { |body_line| parse_test_assertion(body_line) }
          tests << CawfileTest.new(match[1], assertions)
          idx = end_idx + 1
        end

        tests
      end

      private def self.parse_test_assertion(line : String) : CawfileTestAssertion?
        stripped = line.strip
        match = stripped.match(/^assert\s+"([^"]+)"(?:\s*,\s*(.*))?$/)
        return nil unless match

        attrs = parse_keyword_string_args(match[2]? || "")
        CawfileTestAssertion.new(
          match[1],
          input: attrs["input"]? || "",
          equality: attrs["equality"]? || "",
          wait_seconds: attrs["wait"]?.try(&.to_i?) || 0
        )
      end

      private def self.parse_keyword_string_args(raw : String) : Hash(String, String)
        attrs = {} of String => String
        raw.scan(/(\w+)\s*:\s*"((?:\\.|[^"])*)"/) do |match|
          attrs[match[1]] = unescape_quoted_string(match[2])
        end
        raw.scan(/(\w+)\s*:\s*(\d+)/) do |match|
          attrs[match[1]] = match[2]
        end
        attrs
      end

      private def self.unescape_quoted_string(value : String) : String
        value
          .gsub("\\\"", "\"")
          .gsub("\\n", "\n")
          .gsub("\\t", "\t")
          .gsub("\\\\", "\\")
      end

      private def self.service_annotation?(annotations : Array(String)) : Bool
        annotations.any? { |line| line.match(/^\s*@\[Service(?:\([^)]*\))?\]\s*$/) }
      end

      private def self.extract_follow_from_raw(lines : Array(String)) : Array(String)
        lines.each do |line|
          stripped = line.strip
          if stripped.starts_with?("follow")
            if arr_match = stripped.match(/^follow\s+\[(.*)\]/)
              content = arr_match[1]
              return content.split(',').map { |s| s.strip.delete('"') }.reject { |s| s.empty? }
            end
          end
        end
        [] of String
      end

      # Parses `key: ["a", "b"]` or `key = ["a", "b"]` inside a container config
      # into
      # a clean array of unquoted, non-empty strings. Returns [] when absent.
      # `[\s\S]` is used instead of `.` so arrays may span multiple lines.
      private def self.extract_string_array(inner : String, key : String) : Array(String)
        if match = inner.match(/#{key}\s*[:=]\s*\[([\s\S]*?)\]/)
          match[1].split(',').map { |s| s.strip.delete('"') }.reject(&.empty?)
        else
          [] of String
        end
      end

      private def self.extract_container_from_raw(lines : Array(String)) : CawfileContainer?
        if inner = extract_container_block(lines)
          return container_from_inner(inner)
        end

        # The annotation may span multiple lines, so match against the whole blob
        # rather than line-by-line. `[\s\S]*?` crosses newlines up to the first `)]`.
        blob = lines.join('\n')
        container_match = blob.match(/@\[Container(?:\(([\s\S]*?)\))?\]/)
        return nil unless container_match

        inner = container_match[1]?
        return CawfileContainer.new(mode: ContainerMode::Static) unless inner
        container_from_inner(inner)
      end

      private def self.extract_container_block(lines : Array(String)) : String?
        start_idx = nil.as(Int32?)
        lines.each_with_index do |line, idx|
          if line.strip.match(/^\s*container\s+do\s*$/)
            start_idx = idx
            break
          end
        end
        return nil unless start_idx

        body = [] of String
        depth = 1
        lines[(start_idx + 1)..].each do |line|
          stripped = line.strip
          depth += 1 if stripped.match(/\bdo\s*$/)
          if stripped == "end"
            depth -= 1
            break if depth == 0
          end
          body << line if depth > 0
        end

        body.join('\n')
      end

      private def self.container_from_inner(inner : String) : CawfileContainer
        # Check for packages: packages = ["git", "curl"]
        packages = extract_string_array(inner, "packages")
        # Check for files: files = ["script.sh", "config.json"]
        files = extract_string_array(inner, "files")
        # Check for image: image = "alpine:latest" (legacy-compatible)
        image = nil.as(String?)
        if img_match = inner.match(/image\s*[:=]\s*"([^"]+)"/)
          image = img_match[1]
        end
        mode = packages.empty? ? ContainerMode::Static : ContainerMode::Nix
        CawfileContainer.new(mode: mode, packages: packages, image: image, files: files)
      end

      private def self.detect_federation_from_raw(lines : Array(String)) : Bool
        lines.any? { |line| line.includes?("Api::Federation::Inbox") || line.includes?("Api::Federation::Outbox") }
      end

      private def self.detect_models_from_raw(lines : Array(String)) : Bool
        lines.any? { |line| line.includes?("Api::Models") }
      end

      private def self.extract_model_and_validate(
        lines : Array(String),
        workflow_file : String,
        workflow_root : String,
      ) : {String?, String?, String?}
        model = nil.as(String?)
        input_type = nil.as(String?)
        output_type = nil.as(String?)

        lines.each do |line|
          stripped = line.strip

          if model_match = stripped.match(/^\s*@\[Model\(([^)]+)\)\]\s*$/)
            model = resolve_model_annotation(model_match[1].strip, workflow_root)
          end

          if stripped.match(/^\s*@\[Validate\]\s*$/)
            stripped.match(/^\s*@\[Validate\]\s*$/)
          end

          if validate_match = stripped.match(/^\s*@\[Validate\(([^)]+)\)\]\s*$/)
            content = validate_match[1].strip
            parts = content.split(',').map(&.strip)
            input_type = parts[0]? if parts.size >= 1 && !parts[0].empty?
            output_type = parts[1]? if parts.size >= 2 && !parts[1].empty?
          end
        end

        {model, input_type, output_type}
      end

      private def self.resolve_model_annotation(raw : String, workflow_root : String) : String?
        # Direct string model ref: @[Model("openai/gpt-4")]
        if raw.starts_with?('"') && raw.ends_with?('"')
          return raw[1, raw.size - 2]
        end

        # Class-based model ref: @[Model(Kimi.new(version: "2.6", provider: "gonka"))]
        # or @[Model(GPT4)] — shorthand without .new
        class_name = extract_class_name_from_model_arg(raw)
        return nil unless class_name

        # Resolve class against @.meta/models.json
        models_path = File.join(workflow_root, ".meta", "models.json")
        unless File.file?(models_path)
          models_path = File.join(Dir.current, ".meta", "models.json")
        end

        return raw unless File.file?(models_path)

        begin
          json = JSON.parse(File.read(models_path))
          models = json["models"]? || json
          model_def = models[class_name]?
          return raw unless model_def

          provider = model_def["provider"]?.try(&.as_s?) || begin
            # Try to extract provider from .new call if not in json
            extract_provider_from_new_call(raw)
          end
          version = model_def["version"]?.try(&.as_s?)
          model_name = model_def["model"]?.try(&.as_s?) || class_name.downcase

          if provider
            if version && !model_name.includes?(version)
              return "#{provider}/#{model_name}-#{version}"
            else
              return "#{provider}/#{model_name}"
            end
          end
        rescue
        end

        raw
      end

      private def self.extract_class_name_from_model_arg(raw : String) : String?
        return nil if raw.empty?
        return raw if raw.match(/^[A-Z][A-Za-z0-9_]*$/)
        if match = raw.match(/^([A-Z][A-Za-z0-9_]*)\.new\(/)
          return match[1]
        end
        nil
      end

      private def self.extract_provider_from_new_call(raw : String) : String?
        if match = raw.match(/provider:\s*"([^"]+)"/)
          return match[1]
        end
        nil
      end

      private def self.extract_name_from_raw(lines : Array(String)) : String?
        lines.each do |line|
          stripped = line.strip
          if name_match = stripped.match(/^#\+name:\s*(.+)$/)
            return name_match[1].strip
          end
        end
        nil
      end

      private def self.extract_comment_resources(lines : Array(String), name : String?) : Array(CawfileResource)
        resource_name = name.to_s.strip
        resource_id = resource_id_from_name(resource_name)
        return [] of CawfileResource if resource_id.empty?

        [
          CawfileResource.new(
            id: resource_id,
            name: resource_name.empty? ? resource_id : resource_name,
            description: extract_org_header(lines, "description") || "",
            tags: extract_org_tags(lines),
          ),
        ]
      end

      private def self.resource_id_from_name(name : String) : String
        raw = name.strip
        raw = raw.split(/[({\s]/).first?.to_s
        raw.downcase
          .gsub(/[^a-z0-9_-]/, "-")
          .gsub(/-+/, "-")
          .gsub(/^-+|-+$/, "")
      end

      private def self.extract_org_header(lines : Array(String), key : String) : String?
        lines.each do |line|
          stripped = line.strip
          if match = stripped.match(/^#\+#{Regex.escape(key)}:\s*(.+)$/i)
            return match[1].strip
          end
        end
        nil
      end

      private def self.extract_org_tags(lines : Array(String)) : Array(String)
        raw = extract_org_header(lines, "tags") || ""
        normalize_resource_tags(raw.split(';'))
      end

      private def self.extract_triggers(lines : Array(String)) : CawfileTriggers
        CawfileTriggers.new(
          schedule: extract_org_header(lines, "ocawe-schedule"),
          trigger_message: extract_org_header(lines, "ocawe-trigger-message"),
          tags: extract_org_tags(lines),
        )
      end

      private def self.parse_value(raw : String) : RCL::Value
        raw = raw.strip
        if raw.starts_with?('"') && raw.ends_with?('"')
          raw[1, raw.size - 2]
        elsif raw == "true"
          true
        elsif raw == "false"
          false
        elsif raw.match(/^\d+$/)
          raw.to_i
        elsif raw.match(/^\d+\.\d+$/)
          raw.to_f
        elsif raw.starts_with?('[') && raw.ends_with?(']')
          raw[1, raw.size - 2].split(',').map { |s| parse_value(s) }
        else
          raw
        end
      end

      private def self.block_to_rcl_value_h(block : RCL::BlockNode) : Hash(String, RCL::Value)
        hash_out = {} of String => RCL::Value
        block.properties.each do |k, v|
          hash_out[k] = ast_node_to_value(v)
        end
        block.blocks.each do |k, v|
          hash_out[k] = ast_node_to_value(v)
        end
        hash_out
      end

      private def self.ast_node_to_value(node : RCL::ASTNode) : RCL::Value
        case node
        when RCL::StringNode
          node.value
        when RCL::NumberNode
          node.value
        when RCL::BooleanNode
          node.value
        when RCL::ArrayNode
          node.elements.map { |e| ast_node_to_value(e) }
        when RCL::BlockNode
          h = {} of String => RCL::Value
          node.properties.each do |k, v|
            h[k] = ast_node_to_value(v)
          end
          node.blocks.each do |k, v|
            h[k] = ast_node_to_value(v)
          end
          h
        else
          ""
        end
      end

      # Extracts Crystal code (requires, structs, etc.) from Cawfile lines
      # that are outside the workflow block and settings block.
      # This is the code that needs to be compiled alongside the Cawfile.
      private def self.extract_crystal_code(lines : Array(String)) : CrystalLoader
        code_lines = [] of String
        requires = [] of String
        registry_files = [] of String

        in_settings = false
        settings_depth = 0
        in_container = false
        container_depth = 0
        in_workflow = false
        workflow_depth = 0

        lines.each do |line|
          stripped = line.strip

          # Track settings block
          if stripped.match(/^\s*settings\s+do/)
            in_settings = true
            settings_depth = 1
            next
          end
          if in_settings
            if stripped.match(/^do/)
              settings_depth += 1
              next
            end
            if stripped.match(/^end/)
              settings_depth -= 1
              if settings_depth <= 0
                in_settings = false
              end
              next
            end
            next
          end

          # Track container block
          if stripped.match(/^\s*container\s+do\s*$/)
            in_container = true
            container_depth = 1
            next
          end
          if in_container
            if stripped.match(/^do/) || stripped.match(/\bdo\s*$/)
              container_depth += 1
              next
            end
            if stripped.match(/^end/)
              container_depth -= 1
              if container_depth <= 0
                in_container = false
              end
              next
            end
            next
          end

          # Track workflow block
          if stripped.match(/^\s*workflow\s+"[^"]+"\s+do/)
            in_workflow = true
            workflow_depth = 1
            next
          end
          if in_workflow
            if stripped.match(/^\s*(workflow\s+"[^"]+"|settings|if\s+|unless\s+|while\s+|until\s+|parallel|loop|dataset)\b.*\bdo\b/) ||
               stripped.match(/^\s*(if|unless)\s+/)
              workflow_depth += 1
            elsif stripped.match(/^\s*\bend\b/)
              workflow_depth -= 1
              if workflow_depth == 0
                in_workflow = false
              end
            end
            next
          end

          # Skip empty lines and comments
          next if stripped.empty? || stripped.starts_with?("#")
          next if stripped.starts_with?("@[")

          # Extract require statements
          if req_match = stripped.match(/^require\s+"([^"]+)"/)
            module_name = req_match[1]
            requires << module_name
            code_lines << line
            next
          end

          # Collect other Crystal code (structs, modules, etc.)
          code_lines << line
        end

        CrystalLoader.new(
          code: code_lines,
          requires: requires,
          registry_files: registry_files
        )
      end

      # Discovers registry.cr files for each required module.
      # For a module "foo", looks for "foo/registry.cr" relative to the Cawfile directory.
      # For a module "foo/bar", looks for "foo/bar/registry.cr".
      private def self.discover_registry_files(
        requires : Array(String),
        cawfile_dir : String,
      ) : Array(String)
        registry_files = [] of String

        requires.each do |mod|
          # Try direct path: module_name/registry.cr
          registry_path = File.join(cawfile_dir, mod, "registry.cr")
          if File.file?(registry_path)
            registry_files << registry_path
            next
          end

          # Try with .cr extension: module_name.cr/registry.cr (for single-file modules)
          registry_path = File.join(cawfile_dir, "#{mod}.cr", "registry.cr")
          if File.file?(registry_path)
            registry_files << registry_path
            next
          end

          # Try parent directory (for nested modules)
          parts = mod.split('/')
          if parts.size > 1
            registry_path = parts.unshift(cawfile_dir).push("registry.cr").join("/")
            if File.file?(registry_path)
              registry_files << registry_path
            end
          end
        end

        registry_files
      end
    end
  end
end
