require "rcl"

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
      getter files : Array(String)

      def initialize(
        @mode : ContainerMode = ContainerMode::Static,
        @packages : Array(String) = [] of String,
        @image : String? = nil,
        @files : Array(String) = [] of String
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
        @registry_files : Array(String) = [] of String
      )
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
      getter start_settings : Hash(String, RCL::Value)
      # Raw .acd.cr-style DSL source lines inside the workflow block
      getter dsl_source : Array(String)?
      # Federation follow targets extracted from workflow block
      getter follow : Array(String)
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
        @start_settings : Hash(String, RCL::Value) = {} of String => RCL::Value,
        @dsl_source : Array(String)? = nil,
        @follow : Array(String) = [] of String,
        @container : CawfileContainer? = nil,
        @enable_federation : Bool = false,
        @enable_models : Bool = false,
        @input_type : String? = nil,
        @output_type : String? = nil,
        @model : String? = nil,
        @crystal_loader : CrystalLoader? = nil,
        @name : String? = nil
      )
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
        path = find_cawfile(dir)
        return nil unless path

        raw_content = File.read(path)
        raw_lines = raw_content.lines

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
              start_settings: root_config.start_settings,
              follow: follow,
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
                    end
                  end
                end
              end
            end
          end

          workflow_id = "root"
          if wf_block_line = raw_lines.find { |l| l.match(/^\s*workflow\s+"/) }
            workflow_id = wf_block_line.match(/^\s*workflow\s+"([^"]+)"/).try { |m| m[1] } || "root"
          end

          model, input_type, output_type = extract_model_and_validate(raw_lines, path, dir)
          name = extract_name_from_raw(raw_lines)

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
            start_settings: start,
            follow: follow,
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

        raw_content = File.read(path)
        raw_lines = raw_content.lines

        begin
          doc = RCL.parse_string(raw_content)
          workflow_block = find_workflow_block(doc)

          if workflow_block
            root_config = parse_settings_block(doc)
            dsl_lines = extract_workflow_body_lines(raw_lines)
            follow = extract_follow(workflow_block)
            container = extract_container_from_raw(raw_lines)
            name = extract_name_from_raw(raw_lines)

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
              start_settings: root_config.start_settings,
              follow: follow,
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
                    end
                  end
                end
              end
            end
          end

          workflow_id = "root"
          if wf_block_line = raw_lines.find { |l| l.match(/^\s*workflow\s+"/) }
            workflow_id = wf_block_line.match(/^\s*workflow\s+"([^"]+)"/).try { |m| m[1] } || "root"
          end

          model, input_type, output_type = extract_model_and_validate(raw_lines, path, dir)
          name = extract_name_from_raw(raw_lines)

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
            start_settings: start,
            follow: follow,
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
        start = {} of String => RCL::Value

        # Parse properties in settings block
        settings_block.properties.each do |key, value|
          case key
          when "port"
            start["port"] = ast_node_to_value(value)
          when "log_level"
            start["log_level"] = ast_node_to_value(value)
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
              end
            end
          end
        end

        # Parse nested blocks in settings
        settings_block.blocks.each do |name, child|
          case name
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
          start_settings: start
        )
      end

      private def self.find_workflow_block(doc : RCL::Document) : RCL::BlockNode?
        doc.blocks.each do |top_block|
          return top_block if top_block.name == "workflow"
        end
        nil
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
          if stripped.match(/^\s*\bdo\b(?!\w)/)
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

      private def self.extract_container_from_raw(lines : Array(String)) : CawfileContainer?
        text = lines.join("\n")
        if container_match = text.match(/@\[Container\s*\(([\s\S]*?)\)\]/m)
          inner = container_match[1]?
          if inner
            packages = [] of String
            if pkg_match = inner.match(/packages:\s*\[(.*?)\]/m)
              content = pkg_match[1]
              packages = content.split(',').map { |s| s.strip.delete('"') }.reject { |s| s.empty? }
            end
            files = [] of String
            if files_match = inner.match(/files:\s*\[(.*?)\]/m)
              content = files_match[1]
              files = content.split(',').map { |s| s.strip.delete('"') }.reject { |s| s.empty? }
            end
            image = nil
            if img_match = inner.match(/image:\s*"([^"]+)"/m)
              image = img_match[1]
            end
            mode = ContainerMode::Static
            if inner.includes?("mode:")
              if md = inner.match(/mode:\s*"(\w+)"/m)
                mode = ContainerMode.parse(md[1])
              end
            elsif !packages.empty?
              mode = ContainerMode::Nix
            end
            return CawfileContainer.new(mode: mode, packages: packages, image: image, files: files)
          end
          return CawfileContainer.new(mode: ContainerMode::Static)
        end
        nil
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
        workflow_root : String
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

          # Track workflow block
          if stripped.match(/^\s*workflow\s+"[^"]+"\s+do/)
            in_workflow = true
            workflow_depth = 1
            next
          end
          if in_workflow
            if stripped.match(/^\s*\bdo\b/)
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
        cawfile_dir : String
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
