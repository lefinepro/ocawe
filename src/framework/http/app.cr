require "kemal"
require "yaml"
require "set"
require "../discovery/workflow_locator"
require "../agents/loader"
require "../skills/loader"
require "../cognicore/version"
require "../workflows/dsl/crystal_dsl"
require "../workflows/declarative/run"
require "../dataset/store"
require "../dataset/service"
require "../config/settings"
require "../mcp/manager"
require "./endpoints/health"
require "./endpoints/docs"
require "./endpoints/workflows"
require "./endpoints/agents"
require "./endpoints/tools"
require "./endpoints/skills"
require "./endpoints/datasets"
require "./endpoints/runs"
require "./endpoints/hitl"
require "./endpoints/compat"
require "./endpoints/triggers"
require "./endpoints/mcp"

module ACD
  module HTTP
    class App
      RELOAD_INTERVAL_SECONDS = 2.0

      def initialize(
        @port : Int32,
        workflows_root : String? = nil,
        fallback_workflows_root : String? = nil,
        @settings : Cogni::Config::Settings = Cogni::Config::Settings.default
      )
        config = @settings.workflows
        preferred_root = workflows_root || config.preferred_workflows_root
        fallback_root = fallback_workflows_root || config.fallback_workflows_root
        @locator = Discovery::WorkflowLocator.new(preferred_root, fallback_root)
        @agent_loader = Agents::Loader.new
        @skill_loader = Skills::Loader.new
        @workflow_engine = Cogni::Workflow::Engine.new
        @workflow_service = Cogni::Workflow::Service.new(@workflow_engine)
        @dataset_service = Cogni::Dataset::Service.new(build_dataset_store(@settings.datasets))
        @mcp_manager = Cogni::MCP.manager
        @workflow_ids = [] of String
        @workflow_index = {} of String => NamedTuple(
          source_root_type: String,
          workflow_file: String,
          agents: Array(String),
          skills: Array(String),
          tools: Array(String),
          default_model: String?,
          logger: Cogni::Workflow::AnyHash?,
          node_loggers: Hash(String, Cogni::Workflow::AnyHash),
        )
        @skills_index = {} of String => NamedTuple(
          id: String,
          workflow_id: String,
          name: String,
          description: String,
          file_path: String,
        )
        @agents_index = {} of String => NamedTuple(
          id: String,
          workflow_id: String,
          name: String,
          description: String,
          prompt: String,
          model: String?,
          default_model: String?,
          file_path: String,
        )
        @tools_index = [] of NamedTuple(
          id: String,
          workflow_id: String,
        )
        @cache_lock = Mutex.new
      end

      def start
        @mcp_manager.configure(@settings.mcp)
        register_configured_functions!
        reload_cache!
        start_reload_watcher

        Kemal.config.port = @port
        mount_health_endpoints
        mount_docs_endpoints
        mount_workflow_endpoints
        mount_agent_endpoints
        mount_tool_endpoints
        mount_skill_endpoints
        mount_dataset_endpoints
        mount_run_endpoints
        mount_hitl_endpoints
        mount_compat_endpoints
        mount_trigger_endpoints
        mount_mcp_endpoints
        mount_mcp_server_endpoint

        Kemal.run
      end

      private def start_reload_watcher
        fingerprint = current_fingerprint
        spawn do
          loop do
            sleep RELOAD_INTERVAL_SECONDS
            current = current_fingerprint
            next if current == fingerprint

            begin
              reload_cache!
              fingerprint = current
              puts "[cognicore] workflow cache reloaded"
            rescue ex
              STDERR.puts "[cognicore] workflow cache reload failed: #{ex.message}"
            end
          end
        end
      end

      private def reload_cache!
        bundles = @locator.list_workflows
        @dataset_service.reset_dsl_sources!
        rebuilt_engine = Cogni::Workflow::Engine.new
        ids = [] of String
        index = {} of String => NamedTuple(
          source_root_type: String,
          workflow_file: String,
          agents: Array(String),
          skills: Array(String),
          tools: Array(String),
          default_model: String?,
          logger: Cogni::Workflow::AnyHash?,
          node_loggers: Hash(String, Cogni::Workflow::AnyHash),
        )
        skills_index = {} of String => NamedTuple(
          id: String,
          workflow_id: String,
          name: String,
          description: String,
          file_path: String,
        )
        agents_index = {} of String => NamedTuple(
          id: String,
          workflow_id: String,
          name: String,
          description: String,
          prompt: String,
          model: String?,
          default_model: String?,
          file_path: String,
        )
        tools_index = [] of NamedTuple(
          id: String,
          workflow_id: String,
        )
        global_agents = @agent_loader.load_dir("./agents")

        bundles.each do |bundle|
          loaded_agents = merge_agents(global_agents, @agent_loader.load_dir(bundle.agents_dir))
          loaded_skills = @skill_loader.load_dir(bundle.skills_dir)

          ids << bundle.id
          definition = load_workflow_definition(bundle, loaded_agents)
          rebuilt_engine.register(definition)
          tool_ids = [] of String
          definition.default_tools.each { |id| tool_ids << id unless tool_ids.includes?(id) }
          definition.nodes.each do |node|
            next unless node.kind == Cogni::Workflow::NodeKind::Run
            next unless node.metadata["runtime"]?
            tool_ids << node.id unless tool_ids.includes?(node.id)
          end

          loaded_skills.each do |skill|
            qualified_id = "#{bundle.id}:#{skill.id}"
            skills_index[qualified_id] = {
              id: qualified_id,
              workflow_id: bundle.id,
              name: skill.name,
              description: skill.description,
              file_path: skill.file_path,
            }
          end

          loaded_agents.each do |agent|
            qualified_id = "#{bundle.id}:#{agent.id}"
            agents_index[qualified_id] = {
              id: qualified_id,
              workflow_id: bundle.id,
              name: agent.id,
              description: agent.description,
              prompt: agent.prompt,
              model: agent.model,
              default_model: definition.default_model,
              file_path: agent.file_path,
            }
          end

          tool_ids.each do |tool_id|
            tools_index << {
              id: tool_id,
              workflow_id: bundle.id,
            }
          end

          index[bundle.id] = {
            source_root_type: bundle.source_root_type,
            workflow_file: bundle.workflow_file,
            agents: loaded_agents.map(&.id),
            skills: loaded_skills.map(&.id),
            tools: tool_ids,
            default_model: definition.default_model,
            logger: definition.default_logger,
            node_loggers: definition.node_loggers,
          }
        end

        @cache_lock.synchronize do
          @workflow_ids = ids
          @workflow_index = index
          @skills_index = skills_index
          @agents_index = agents_index
          @tools_index = tools_index
          @workflow_engine = rebuilt_engine
          @workflow_service = Cogni::Workflow::Service.new(@workflow_engine)
        end
      end

      private def workflow_ids : Array(String)
        @cache_lock.synchronize { @workflow_ids.dup }
      end

      private def workflow_by_id(workflow_id : String)
        @cache_lock.synchronize { @workflow_index[workflow_id]? }
      end

      private def tools : Array(NamedTuple(id: String, workflow_id: String))
        @cache_lock.synchronize { @tools_index.dup }
      end

      private def skills : Array(NamedTuple(id: String, workflow_id: String, name: String, description: String, file_path: String))
        @cache_lock.synchronize { @skills_index.values.to_a }
      end

      private def skill_by_id(skill_id : String)
        @cache_lock.synchronize { @skills_index[skill_id]? }
      end

      private def agents : Array(NamedTuple(id: String, workflow_id: String, name: String, description: String, prompt: String, model: String?, default_model: String?, file_path: String))
        @cache_lock.synchronize { @agents_index.values.to_a }
      end

      private def agent_by_id(agent_id : String)
        @cache_lock.synchronize { @agents_index[agent_id]? }
      end

      private def merge_agents(
        global_agents : Array(ACD::Agents::LoadedAgent),
        local_agents : Array(ACD::Agents::LoadedAgent)
      ) : Array(ACD::Agents::LoadedAgent)
        merged = {} of String => ACD::Agents::LoadedAgent
        global_agents.each { |agent| merged[agent.id] = agent }
        local_agents.each { |agent| merged[agent.id] = agent }
        merged.values.to_a
      end

      private def register_configured_functions! : Nil
        config = @settings
        Cogni::RegistryApi.reset_all!

        config.functions.each do |name, handler|
          Cogni::RegistryApi.register_system_function(name, &handler)
        end
      end

      private def build_dataset_store(config : Cogni::Config::DatasetSettings) : Cogni::Dataset::Store::Base
        case config.adapter.strip.downcase
        when "", "memory"
          Cogni::Dataset::Store::InMemory.new
        when "file"
          Cogni::Dataset::Store::File.new(config.file_root)
        else
          raise "unsupported dataset adapter: #{config.adapter}"
        end
      end

      private def current_fingerprint : String
        bundles = @locator.list_workflows
        file_count = 0
        latest_mtime = 0_i64

        global_files = [] of String
        global_files.concat(glob_files("./agents", "*.md"))
        global_files.concat(glob_files("./tools", "*"))

        global_files.each do |path|
          next unless File.exists?(path)
          file_count += 1
          mtime = File.info(path).modification_time.to_unix_ms
          latest_mtime = mtime if mtime > latest_mtime
        end

        bundles.each do |bundle|
          files = [bundle.workflow_file] of String
          files.concat(glob_files(bundle.agents_dir, "*.md"))
          files.concat(glob_files(bundle.skills_dir, "*.md"))
          files.concat(glob_files(File.join(bundle.root_path, "tools"), "*"))

          files.each do |path|
            next unless File.exists?(path)
            file_count += 1
            mtime = File.info(path).modification_time.to_unix_ms
            latest_mtime = mtime if mtime > latest_mtime
          end
        end

        "#{bundles.size}:#{file_count}:#{latest_mtime}"
      end

      private def glob_files(root : String, pattern : String) : Array(String)
        return [] of String unless Dir.exists?(root)

        paths = [] of String
        Dir.glob(File.join(root, pattern)) do |path|
          paths << path if File.file?(path)
        end
        paths
      end

      private def not_implemented(env, message : String) : String
        env.response.status_code = 501
        env.response.content_type = "application/json"
        {error: {type: "not_implemented", message: message}}.to_json
      end

      private def json_body(env) : Cogni::Workflow::AnyHash
        raw = env.request.body.try(&.gets_to_end).to_s
        return {} of String => JSON::Any if raw.strip.empty?
        parsed = JSON.parse(raw)
        parsed.as_h? || {} of String => JSON::Any
      rescue
        {} of String => JSON::Any
      end

      private def parse_node_selector(value : JSON::Any?) : (String | Array(String) | Nil)
        return nil unless value
        if as_string = value.as_s?
          return as_string
        end
        if as_array = value.as_a?
          return as_array.compact_map(&.as_s?)
        end
        nil
      end

      private def with_workflow_errors(env, &block : -> T) : (T | String) forall T
        block.call
      rescue ex
        message = ex.message || "workflow request failed"
        if message.includes?("unknown workflow") || message.includes?("unknown workflow bundle")
          env.response.status_code = 404
          env.response.content_type = "application/json"
          return {error: {type: "not_found", message: message}}.to_json
        end
        if message.includes?("unknown node") || message.includes?("requires node")
          env.response.status_code = 400
          env.response.content_type = "application/json"
          return {error: {type: "bad_request", message: message}}.to_json
        end
        env.response.status_code = 422
        env.response.content_type = "application/json"
        return {error: {type: "workflow_error", message: message}}.to_json
      end

      private def load_workflow_definition(bundle : Discovery::WorkflowBundle, loaded_agents : Array(Agents::LoadedAgent)) : Cogni::Workflow::WorkflowDefinition
        workflow = Cogni::Workflow.create_workflow(bundle.id, "Loaded from #{bundle.workflow_file}")
        agent_index = {} of String => Agents::LoadedAgent
        loaded_agents.each { |agent| agent_index[agent.id] = agent }

        # Read all lines for multi-line block parsing
        lines = File.read_lines(bundle.workflow_file)

        # Create a parsing context
        ctx = WorkflowParserContext.new(
          workflow: workflow,
          agent_index: agent_index,
          workflow_file: bundle.workflow_file,
          workflow_root: bundle.root_path,
          lines: lines,
          dataset_service: @dataset_service
        )

        parse_workflow_body(ctx, 0, lines.size)

        workflow.commit
        enforce_enabled_node_kinds!(workflow, bundle.workflow_file)
        workflow
      end

      private def enforce_enabled_node_kinds!(workflow : Cogni::Workflow::WorkflowDefinition, workflow_file : String) : Nil
        enabled = @settings.node_kinds.enabled
        return if enabled.empty?

        allowed = enabled.map(&.strip.downcase).to_set
        workflow.nodes.each do |node|
          key = node.kind.to_s.downcase
          unless allowed.includes?(key)
            raise "#{workflow_file}: node kind '#{key}' is disabled by config"
          end
        end
      end

      # Parser context for workflow DSL
      private struct WorkflowParserContext
        getter workflow : Cogni::Workflow::WorkflowDefinition
        getter agent_index : Hash(String, Agents::LoadedAgent)
        getter workflow_file : String
        getter workflow_root : String
        getter lines : Array(String)
        getter dataset_service : Cogni::Dataset::Service
        property last_agent_id : String?

        def initialize(
          @workflow : Cogni::Workflow::WorkflowDefinition,
          @agent_index : Hash(String, Agents::LoadedAgent),
          @workflow_file : String,
          @workflow_root : String,
          @lines : Array(String),
          @dataset_service : Cogni::Dataset::Service
        )
          @last_agent_id = nil
        end
      end

      # Parse workflow body between start_line and end_line
      private def parse_workflow_body(ctx : WorkflowParserContext, start_line : Int32, end_line : Int32) : Int32
        run_pattern = /^\s*run\s+"([^"]+)"(.*)$/
        skill_pattern = /^\s*skill\s+"([^"]+)"(?:\s*,\s*agent:\s*"([^"]+)")?/
        rag_pattern = /^\s*rag\s+"([^"]+)"(?:\s*,\s*config:\s*(\{.*\}))?/
        suspend_pattern = /^\s*suspend\s+"([^"]+)"(.*)$/
        reserved_keywords = Set{
          "workflow", "do", "end", "struct", "class", "module",
          "include", "extend", "getter", "setter", "property",
          "alias", "enum", "lib", "fun", "require",
          "agent", "skill", "run", "voice", "rag", "suspend", "dataset",
          "input_type", "output_type", "input_validate", "output_validate",
          "parallel", "if", "elsif", "else", "while", "unless", "until", "loop",
        }

        i = start_line
        while i < end_line
          raw = ctx.lines[i]
          line = raw.strip
          i += 1

          next if line.empty? || line.starts_with?("#")

          # Handle parallel do...end block
          if line.match(/^\s*parallel\s+do\s*$/)
            block_end = find_block_end(ctx.lines, i, end_line)
            parse_parallel_block(ctx, i, block_end)
            i = block_end + 1
            next
          end

          # Handle if/elsif/else conditional blocks
          if line.match(/^\s*if\s+/)
            block_end = find_conditional_end(ctx.lines, i - 1, end_line)
            parse_conditional_block(ctx, i - 1, block_end)
            i = block_end + 1
            next
          end

          # Handle unless conditional block
          if line.match(/^\s*unless\s+/)
            block_end = find_unless_end(ctx.lines, i - 1, end_line)
            parse_unless_block(ctx, i - 1, block_end)
            i = block_end + 1
            next
          end

          # Handle while do...end loop
          if line.match(/^\s*while\s+.+\s+do\s*$/)
            block_end = find_block_end(ctx.lines, i, end_line)
            parse_while_block(ctx, i - 1, block_end)
            i = block_end + 1
            next
          end

          # Handle until do...end loop
          if line.match(/^\s*until\s+.+\s+do\s*$/)
            block_end = find_block_end(ctx.lines, i, end_line)
            parse_until_block(ctx, i - 1, block_end)
            i = block_end + 1
            next
          end

          # Handle loop do...end loop
          if line.match(/^\s*loop\s+do\s*$/)
            block_end = find_block_end(ctx.lines, i, end_line)
            parse_loop_block(ctx, i - 1, block_end)
            i = block_end + 1
            next
          end

          if match = line.match(/^\s*dataset\s+"([^"]+)"\s+do\s*$/)
            dataset_id = match[1]
            block_end = find_block_end(ctx.lines, i, end_line)
            parse_dataset_block(ctx, dataset_id, i, block_end)
            i = block_end + 1
            next
          end

          if match = line.match(/^\s*agent\s+"([^"]+)"(.*)$/)
            agent_id = match[1]
            tail = match[2]? || ""
            loaded = ctx.agent_index[agent_id]?
            params = parse_line_params(tail, ctx.workflow_file, "agent #{agent_id}")
            if params["custom_fn"]?
              raise "#{ctx.workflow_file}: `custom_fn` is not supported for agent. Register a function and call it via `run \"function_name\"`."
            end
            model = parse_optional_string(params["model"]?) || loaded.try(&.model)
            prompt = parse_optional_string(params["prompt"]?) || loaded.try(&.prompt)
            input_schema = resolve_agent_schema(
              params["input_schema"]?,
              loaded,
              kind: "input",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )
            output_schema = resolve_agent_schema(
              params["output_schema"]?,
              loaded,
              kind: "output",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )
            resume_schema = resolve_agent_schema(
              params["resume_schema"]?,
              loaded,
              kind: "resume",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )

            ctx.workflow.agent(
              agent_id,
              prompt: prompt,
              model: model,
              resume_schema: resume_schema,
              voice_config: loaded.try(&.voice_config),
              guardrails_config: loaded.try(&.guardrails_config),
              input_schema: input_schema,
              output_schema: output_schema,
            )
            ctx.last_agent_id = agent_id
            next
          end
          # Resource allocation annotation: @[Resources(model: "...", skill: ["..."], tool: ["..."])]
          if line.match(/^\s*@\[Resources\(/)
            resources_annotation = line
            unless resources_annotation.includes?(")]")
              while i < end_line
                continuation = ctx.lines[i].strip
                resources_annotation = "#{resources_annotation} #{continuation}"
                i += 1
                break if continuation.includes?(")]")
              end
            end

            match = resources_annotation.match(/^\s*@\[Resources\((.*)\)\]\s*$/)
            raise "#{ctx.workflow_file}: invalid Resources annotation syntax '#{resources_annotation}'" unless match

            params = parse_resources_annotation_params(match[1])
            model = params[:model]
            skill = params[:skill]
            tool = params[:tool]
            ctx.workflow.use(model: model, skill: skill, tool: tool)
            next
          end
          if line.match(/^\s*@resources\s+/)
            raise "#{ctx.workflow_file}: `@resources` is not a Crystal annotation. Use `@[Resources(model: \"...\", skill: [...], tool: [...])]`."
          end
          if line.match(/^\s*use\s+/)
            raise "#{ctx.workflow_file}: `use` keyword is deprecated. Use `@[Resources(model: \"...\", skill: [...], tool: [...])]`."
          end
          if match = line.match(skill_pattern)
            ctx.workflow.skill(match[1], agent: match[2]?)
            next
          end
          if match = line.match(/^\s*voice\s+"([^"]+)"(.*)$/)
            voice_id = match[1]
            tail = match[2]? || ""
            params = parse_line_params(tail, ctx.workflow_file, "voice #{voice_id}")

            inline_config = params["config"]?.try { |value| parse_runtime_object(value, ctx.workflow_file) } || ({} of String => JSON::Any)
            requested_agent_id = parse_optional_string(params["agent"]?) || ctx.last_agent_id
            agent_voice = requested_agent_id.try { |id| ctx.agent_index[id]?.try(&.voice_config) } || ({} of String => JSON::Any)
            config = agent_voice.merge(inline_config) { |_k, _left, right| right }

            ctx.workflow.voice(voice_id, config: config)
            next
          end
          if match = line.match(rag_pattern)
            config = match[2]? ? parse_runtime_object(match[2], ctx.workflow_file) : ({} of String => JSON::Any)
            ctx.workflow.rag(match[1], config: config)
            next
          end
          if match = line.match(run_pattern)
            ref = match[1]
            tail = match[2]? || ""
            params = parse_line_params(tail, ctx.workflow_file, "run #{ref}")
            runtime = params["runtime"]?.try { |value| parse_runtime_object(value, ctx.workflow_file) }
            env = params["env"]?.try { |value| parse_runtime_object(value, ctx.workflow_file) }
            input_schema = compile_optional_function_schema(params["input_schema"]?, ctx.workflow_file, "run #{ref}", "input")
            output_schema = compile_optional_function_schema(params["output_schema"]?, ctx.workflow_file, "run #{ref}", "output")
            run_params = extract_named_args(params, Set{"runtime", "env", "input_schema", "output_schema"}, ctx.workflow_file)

            ctx.workflow.run(
              ref,
              runtime: runtime,
              env: env,
              workflow_root: ctx.workflow_root,
              params: run_params,
              input_schema: input_schema,
              output_schema: output_schema,
            )
            next
          end
          if line.starts_with?("tool ")
            raise "#{ctx.workflow_file}: `tool` is removed from DSL. Use `run \"function_or_path_or_inline\"` with optional `runtime` and `env`."
          end
          if match = line.match(suspend_pattern)
            suspend_id = match[1]
            tail = match[2]? || ""
            params = parse_line_params(tail, ctx.workflow_file, "suspend #{suspend_id}")
            reason = parse_optional_string(params["reason"]?) || "human input required"
            resume_schema = resolve_suspend_resume_schema(
              params["resume_schema"]?,
              ctx: ctx,
              suspend_id: suspend_id
            )
            ctx.workflow.suspend(suspend_id, reason: reason, resume_schema: resume_schema)
            next
          end
          if line.match(/^\s*approve\s+/)
            raise "#{ctx.workflow_file}: `approve` is deprecated. Use `suspend \"id\", reason: \"...\", resume_schema: ...`."
            next
          end
          if match = line.match(/^([a-z][a-z0-9_]*)(.*)$/)
            fn_name = match[1]
            next if reserved_keywords.includes?(fn_name)
            raise "#{ctx.workflow_file}: bare function syntax is removed. Use `run \"#{fn_name}\"`."
          end
        end

        i
      end

      # Find the end of a do...end block
      private def find_block_end(lines : Array(String), start_line : Int32, max_line : Int32) : Int32
        depth = 1
        i = start_line
        while i < max_line && depth > 0
          line = lines[i].strip
          depth += 1 if line.match(/\bdo\s*$/)
          depth -= 1 if line == "end"
          i += 1
        end
        i - 1
      end

      # Find the end of an if/elsif/else...end block
      private def find_conditional_end(lines : Array(String), start_line : Int32, max_line : Int32) : Int32
        depth = 1
        i = start_line + 1
        while i < max_line && depth > 0
          line = lines[i].strip
          depth += 1 if line.match(/^\s*if\s+/)
          depth -= 1 if line == "end"
          i += 1
        end
        i - 1
      end

      # Find the end of an unless...else...end block
      private def find_unless_end(lines : Array(String), start_line : Int32, max_line : Int32) : Int32
        depth = 1
        i = start_line + 1
        while i < max_line && depth > 0
          line = lines[i].strip
          depth += 1 if line.match(/^\s*(if|unless)\s+/)
          depth -= 1 if line == "end"
          i += 1
        end
        i - 1
      end

      private def parse_dataset_block(ctx : WorkflowParserContext, dataset_id : String, start_line : Int32, end_line : Int32) : Nil
        description = nil.as(String?)
        schema_source = nil.as(String?)
        seed_items = [] of Cogni::Dataset::AnyHash

        i = start_line
        while i < end_line
          line = ctx.lines[i].strip
          i += 1
          next if line.empty? || line.starts_with?("#")

          if match = line.match(/^\s*description\s+"([^"]+)"\s*$/)
            description = match[1]
            next
          end

          if line.match(/^\s*schema\s+/)
            initial = line.sub(/^\s*schema\s+/, "")
            collected = collect_balanced_expression(initial, ctx.lines, i, end_line, "dataset #{dataset_id} schema", ctx.workflow_file)
            schema_source = collected[:value]
            i = collected[:next_index]
            next
          end

          if line.match(/^\s*item\s*\(/)
            collected = collect_balanced_expression(line, ctx.lines, i, end_line, "dataset #{dataset_id} item", ctx.workflow_file)
            expression = collected[:value]
            i = collected[:next_index]
            match = expression.match(/^\s*item\s*\((.*)\)\s*$/)
            raise "#{ctx.workflow_file}: invalid dataset item syntax '#{expression}'" unless match
            parsed = parse_runtime_literal(match[1], ctx.workflow_file)
            hash = parsed.as_h?
            raise "#{ctx.workflow_file}: dataset item must be an object" unless hash
            seed_items << hash
            next
          end

          if line.match(/^\s*items\s*\(/)
            collected = collect_balanced_expression(line, ctx.lines, i, end_line, "dataset #{dataset_id} items", ctx.workflow_file)
            expression = collected[:value]
            i = collected[:next_index]
            match = expression.match(/^\s*items\s*\((.*)\)\s*$/)
            raise "#{ctx.workflow_file}: invalid dataset items syntax '#{expression}'" unless match
            parsed = parse_runtime_literal(match[1], ctx.workflow_file)
            array = parsed.as_a?
            raise "#{ctx.workflow_file}: dataset items must be an array of objects" unless array
            array.each do |entry|
              hash = entry.as_h?
              raise "#{ctx.workflow_file}: dataset items must be an array of objects" unless hash
              seed_items << hash
            end
            next
          end

          raise "#{ctx.workflow_file}: unsupported dataset directive '#{line}'"
        end

        ctx.dataset_service.register_from_dsl(
          dataset_id,
          source_file: ctx.workflow_file,
          description: description,
          schema_source: schema_source,
          seed_items: seed_items,
        )
      end

      # Parse a parallel do...end block
      private def parse_parallel_block(ctx : WorkflowParserContext, start_line : Int32, end_line : Int32) : Nil
        # Collect nodes defined in the parallel block
        parallel_nodes = [] of Cogni::Workflow::WorkflowNode

        i = start_line
        while i < end_line
          raw = ctx.lines[i]
          line = raw.strip
          i += 1

          next if line.empty? || line.starts_with?("#")
          next if line == "end"

          # Parse agent nodes inside parallel block
          if match = line.match(/^\s*agent\s+"([^"]+)"(.*)$/)
            agent_id = match[1]
            tail = match[2]? || ""
            loaded = ctx.agent_index[agent_id]?
            params = parse_line_params(tail, ctx.workflow_file, "agent #{agent_id}")
            model = parse_optional_string(params["model"]?) || loaded.try(&.model)
            prompt = parse_optional_string(params["prompt"]?) || loaded.try(&.prompt)
            input_schema = resolve_agent_schema(
              params["input_schema"]?,
              loaded,
              kind: "input",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )
            output_schema = resolve_agent_schema(
              params["output_schema"]?,
              loaded,
              kind: "output",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )
            resume_schema = resolve_agent_schema(
              params["resume_schema"]?,
              loaded,
              kind: "resume",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )

            node = create_agent_node(
              agent_id,
              prompt: prompt,
              model: model,
              resume_schema: resume_schema,
              voice_config: loaded.try(&.voice_config),
              guardrails_config: loaded.try(&.guardrails_config),
              input_schema: input_schema,
              output_schema: output_schema,
              default_model: ctx.workflow.default_model
            )
            parallel_nodes << node
            next
          end

          if match = line.match(/^\s*run\s+"([^"]+)"(.*)$/)
            ref = match[1]
            tail = match[2]? || ""
            params = parse_line_params(tail, ctx.workflow_file, "run #{ref}")
            runtime = params["runtime"]?.try { |value| parse_runtime_object(value, ctx.workflow_file) }
            env = params["env"]?.try { |value| parse_runtime_object(value, ctx.workflow_file) }
            input_schema = compile_optional_function_schema(params["input_schema"]?, ctx.workflow_file, "run #{ref}", "input")
            output_schema = compile_optional_function_schema(params["output_schema"]?, ctx.workflow_file, "run #{ref}", "output")
            run_params = extract_named_args(params, Set{"runtime", "env", "input_schema", "output_schema"}, ctx.workflow_file)
            parallel_nodes << create_run_node(
              ref,
              runtime: runtime,
              env: env,
              params: run_params,
              input_schema: input_schema,
              output_schema: output_schema,
              workflow_root: ctx.workflow_root
            )
            next
          end
        end

        # Add the parallel node to the workflow
        ctx.workflow.parallel(parallel_nodes) unless parallel_nodes.empty?
      end

      # Parse if/elsif/else conditional block
      private def parse_conditional_block(ctx : WorkflowParserContext, start_line : Int32, end_line : Int32) : Nil
        conditions = [] of Tuple(String, Cogni::Workflow::WorkflowNode)
        otherwise_node = nil.as(Cogni::Workflow::WorkflowNode?)

        i = start_line
        current_condition = nil.as(String?)
        current_nodes = [] of Cogni::Workflow::WorkflowNode
        in_else = false

        while i <= end_line
          raw = ctx.lines[i]
          line = raw.strip
          i += 1

          next if line.empty? || line.starts_with?("#")

          if match = line.match(/^\s*if\s+(.+)$/)
            current_condition = match[1].strip
            next
          end

          if match = line.match(/^\s*elsif\s+(.+)$/)
            # Save previous condition
            if current_condition && !current_nodes.empty?
              node = wrap_nodes_in_control(current_nodes, "if-branch")
              conditions << {current_condition, node}
            end
            current_condition = match[1].strip
            current_nodes = [] of Cogni::Workflow::WorkflowNode
            next
          end

          if line == "else"
            # Save previous condition
            if current_condition && !current_nodes.empty?
              node = wrap_nodes_in_control(current_nodes, "if-branch")
              conditions << {current_condition, node}
            end
            current_condition = nil
            current_nodes = [] of Cogni::Workflow::WorkflowNode
            in_else = true
            next
          end

          if line == "end"
            # Save final condition or else block
            if in_else && !current_nodes.empty?
              otherwise_node = wrap_nodes_in_control(current_nodes, "else-branch")
            elsif current_condition && !current_nodes.empty?
              node = wrap_nodes_in_control(current_nodes, "if-branch")
              conditions << {current_condition, node}
            end
            break
          end

          # Parse agent nodes inside conditional block
          if match = line.match(/^\s*agent\s+"([^"]+)"(.*)$/)
            agent_id = match[1]
            tail = match[2]? || ""
            loaded = ctx.agent_index[agent_id]?
            params = parse_line_params(tail, ctx.workflow_file, "agent #{agent_id}")
            model = parse_optional_string(params["model"]?) || loaded.try(&.model)
            prompt = parse_optional_string(params["prompt"]?) || loaded.try(&.prompt)
            input_schema = resolve_agent_schema(
              params["input_schema"]?,
              loaded,
              kind: "input",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )
            output_schema = resolve_agent_schema(
              params["output_schema"]?,
              loaded,
              kind: "output",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )
            resume_schema = resolve_agent_schema(
              params["resume_schema"]?,
              loaded,
              kind: "resume",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )

            node = create_agent_node(
              agent_id,
              prompt: prompt,
              model: model,
              resume_schema: resume_schema,
              voice_config: loaded.try(&.voice_config),
              guardrails_config: loaded.try(&.guardrails_config),
              input_schema: input_schema,
              output_schema: output_schema,
              default_model: ctx.workflow.default_model
            )
            current_nodes << node
            next
          end

          if match = line.match(/^\s*run\s+"([^"]+)"(.*)$/)
            ref = match[1]
            tail = match[2]? || ""
            params = parse_line_params(tail, ctx.workflow_file, "run #{ref}")
            runtime = params["runtime"]?.try { |value| parse_runtime_object(value, ctx.workflow_file) }
            env = params["env"]?.try { |value| parse_runtime_object(value, ctx.workflow_file) }
            input_schema = compile_optional_function_schema(params["input_schema"]?, ctx.workflow_file, "run #{ref}", "input")
            output_schema = compile_optional_function_schema(params["output_schema"]?, ctx.workflow_file, "run #{ref}", "output")
            run_params = extract_named_args(params, Set{"runtime", "env", "input_schema", "output_schema"}, ctx.workflow_file)
            current_nodes << create_run_node(
              ref,
              runtime: runtime,
              env: env,
              params: run_params,
              input_schema: input_schema,
              output_schema: output_schema,
              workflow_root: ctx.workflow_root
            )
          end
        end

        return if conditions.empty? && otherwise_node.nil?

        conditional_node = Cogni::Workflow::WorkflowNode.new("if-#{start_line}", Cogni::Workflow::NodeKind::Control) do |node_ctx|
          selected = conditions.find { |(condition, _)| evaluate_dsl_condition(condition, node_ctx) }.try(&.[1]) || otherwise_node
          if selected
            selected.execute(node_ctx)
          else
            Cogni::Workflow::WorkflowNodeResult.continue
          end
        end
        ctx.workflow.step(conditional_node)
      end

      # Parse unless...else...end conditional block
      private def parse_unless_block(ctx : WorkflowParserContext, start_line : Int32, end_line : Int32) : Nil
        i = start_line
        condition = nil.as(String?)
        unless_nodes = [] of Cogni::Workflow::WorkflowNode
        else_nodes = [] of Cogni::Workflow::WorkflowNode
        in_else = false

        while i <= end_line
          raw = ctx.lines[i]
          line = raw.strip
          i += 1

          next if line.empty? || line.starts_with?("#")

          if match = line.match(/^\s*unless\s+(.+)$/)
            condition = match[1].strip
            next
          end

          if line == "else"
            in_else = true
            next
          end

          if line == "end"
            break
          end

          # Parse agent nodes inside unless block
          if match = line.match(/^\s*agent\s+"([^"]+)"(.*)$/)
            agent_id = match[1]
            tail = match[2]? || ""
            loaded = ctx.agent_index[agent_id]?
            params = parse_line_params(tail, ctx.workflow_file, "agent #{agent_id}")
            model = parse_optional_string(params["model"]?) || loaded.try(&.model)
            prompt = parse_optional_string(params["prompt"]?) || loaded.try(&.prompt)
            input_schema = resolve_agent_schema(
              params["input_schema"]?,
              loaded,
              kind: "input",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )
            output_schema = resolve_agent_schema(
              params["output_schema"]?,
              loaded,
              kind: "output",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )
            resume_schema = resolve_agent_schema(
              params["resume_schema"]?,
              loaded,
              kind: "resume",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )

            node = create_agent_node(
              agent_id,
              prompt: prompt,
              model: model,
              resume_schema: resume_schema,
              voice_config: loaded.try(&.voice_config),
              guardrails_config: loaded.try(&.guardrails_config),
              input_schema: input_schema,
              output_schema: output_schema,
              default_model: ctx.workflow.default_model
            )

            if in_else
              else_nodes << node
            else
              unless_nodes << node
            end
            next
          end

          if match = line.match(/^\s*run\s+"([^"]+)"(.*)$/)
            ref = match[1]
            tail = match[2]? || ""
            params = parse_line_params(tail, ctx.workflow_file, "run #{ref}")
            runtime = params["runtime"]?.try { |value| parse_runtime_object(value, ctx.workflow_file) }
            env = params["env"]?.try { |value| parse_runtime_object(value, ctx.workflow_file) }
            input_schema = compile_optional_function_schema(params["input_schema"]?, ctx.workflow_file, "run #{ref}", "input")
            output_schema = compile_optional_function_schema(params["output_schema"]?, ctx.workflow_file, "run #{ref}", "output")
            run_params = extract_named_args(params, Set{"runtime", "env", "input_schema", "output_schema"}, ctx.workflow_file)

            node = create_run_node(
              ref,
              runtime: runtime,
              env: env,
              params: run_params,
              input_schema: input_schema,
              output_schema: output_schema,
              workflow_root: ctx.workflow_root
            )

            if in_else
              else_nodes << node
            else
              unless_nodes << node
            end
          end
        end

        return unless condition && !unless_nodes.empty?
        condition_value = condition.not_nil!

        unless_branch_node = wrap_nodes_in_control(unless_nodes, "unless-branch")
        else_branch_node = else_nodes.empty? ? nil : wrap_nodes_in_control(else_nodes, "else-branch")
        control_node = Cogni::Workflow::WorkflowNode.new("unless-#{start_line}", Cogni::Workflow::NodeKind::Control) do |node_ctx|
          selected = evaluate_dsl_condition(condition_value, node_ctx) ? else_branch_node : unless_branch_node
          if selected
            selected.execute(node_ctx)
          else
            Cogni::Workflow::WorkflowNodeResult.continue
          end
        end
        ctx.workflow.step(control_node)
      end

      # Parse while condition do...end loop
      private def parse_while_block(ctx : WorkflowParserContext, start_line : Int32, end_line : Int32) : Nil
        raw = ctx.lines[start_line]
        line = raw.strip

        # Extract condition from "while <condition> do"
        match = line.match(/^\s*while\s+(.+)\s+do\s*$/)
        return unless match
        condition = match[1].strip

        loop_nodes = [] of Cogni::Workflow::WorkflowNode

        i = start_line + 1
        while i <= end_line
          raw = ctx.lines[i]
          line = raw.strip
          i += 1

          next if line.empty? || line.starts_with?("#")
          next if line == "end"

          # Parse agent nodes inside while block
          if match = line.match(/^\s*agent\s+"([^"]+)"(.*)$/)
            agent_id = match[1]
            tail = match[2]? || ""
            loaded = ctx.agent_index[agent_id]?
            params = parse_line_params(tail, ctx.workflow_file, "agent #{agent_id}")
            model = parse_optional_string(params["model"]?) || loaded.try(&.model)
            prompt = parse_optional_string(params["prompt"]?) || loaded.try(&.prompt)
            input_schema = resolve_agent_schema(
              params["input_schema"]?,
              loaded,
              kind: "input",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )
            output_schema = resolve_agent_schema(
              params["output_schema"]?,
              loaded,
              kind: "output",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )
            resume_schema = resolve_agent_schema(
              params["resume_schema"]?,
              loaded,
              kind: "resume",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )

            node = create_agent_node(
              agent_id,
              prompt: prompt,
              model: model,
              resume_schema: resume_schema,
              voice_config: loaded.try(&.voice_config),
              guardrails_config: loaded.try(&.guardrails_config),
              input_schema: input_schema,
              output_schema: output_schema,
              default_model: ctx.workflow.default_model
            )
            loop_nodes << node
            next
          end

          if match = line.match(/^\s*run\s+"([^"]+)"(.*)$/)
            ref = match[1]
            tail = match[2]? || ""
            params = parse_line_params(tail, ctx.workflow_file, "run #{ref}")
            runtime = params["runtime"]?.try { |value| parse_runtime_object(value, ctx.workflow_file) }
            env = params["env"]?.try { |value| parse_runtime_object(value, ctx.workflow_file) }
            input_schema = compile_optional_function_schema(params["input_schema"]?, ctx.workflow_file, "run #{ref}", "input")
            output_schema = compile_optional_function_schema(params["output_schema"]?, ctx.workflow_file, "run #{ref}", "output")
            run_params = extract_named_args(params, Set{"runtime", "env", "input_schema", "output_schema"}, ctx.workflow_file)

            loop_nodes << create_run_node(
              ref,
              runtime: runtime,
              env: env,
              params: run_params,
              input_schema: input_schema,
              output_schema: output_schema,
              workflow_root: ctx.workflow_root
            )
          end
        end

        return if loop_nodes.empty?

        loop_body = wrap_nodes_in_control(loop_nodes, "while-body")
        control_node = Cogni::Workflow::WorkflowNode.new("while-#{start_line}", Cogni::Workflow::NodeKind::Control) do |node_ctx|
          iterations = 0
          merged = {} of String => JSON::Any
          result = Cogni::Workflow::WorkflowNodeResult.continue

          while evaluate_dsl_condition(condition, with_state(node_ctx, merged)) && iterations < 100
            iterations += 1
            result = loop_body.execute(with_state(node_ctx, merged))
            break if result.action != Cogni::Workflow::NodeAction::Continue.to_s.downcase
            if data = result.data
              data.each { |k, v| merged[k] = v }
            end
          end

          if result.action == Cogni::Workflow::NodeAction::Continue.to_s.downcase
            Cogni::Workflow::WorkflowNodeResult.continue(merged)
          else
            result
          end
        end
        ctx.workflow.step(control_node)
      end

      # Parse until condition do...end loop
      private def parse_until_block(ctx : WorkflowParserContext, start_line : Int32, end_line : Int32) : Nil
        raw = ctx.lines[start_line]
        line = raw.strip

        # Extract condition from "until <condition> do"
        match = line.match(/^\s*until\s+(.+)\s+do\s*$/)
        return unless match
        condition = match[1].strip

        loop_nodes = [] of Cogni::Workflow::WorkflowNode

        i = start_line + 1
        while i <= end_line
          raw = ctx.lines[i]
          line = raw.strip
          i += 1

          next if line.empty? || line.starts_with?("#")
          next if line == "end"

          # Parse agent nodes inside until block
          if match = line.match(/^\s*agent\s+"([^"]+)"(.*)$/)
            agent_id = match[1]
            tail = match[2]? || ""
            loaded = ctx.agent_index[agent_id]?
            params = parse_line_params(tail, ctx.workflow_file, "agent #{agent_id}")
            model = parse_optional_string(params["model"]?) || loaded.try(&.model)
            prompt = parse_optional_string(params["prompt"]?) || loaded.try(&.prompt)
            input_schema = resolve_agent_schema(
              params["input_schema"]?,
              loaded,
              kind: "input",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )
            output_schema = resolve_agent_schema(
              params["output_schema"]?,
              loaded,
              kind: "output",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )
            resume_schema = resolve_agent_schema(
              params["resume_schema"]?,
              loaded,
              kind: "resume",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )

            node = create_agent_node(
              agent_id,
              prompt: prompt,
              model: model,
              resume_schema: resume_schema,
              voice_config: loaded.try(&.voice_config),
              guardrails_config: loaded.try(&.guardrails_config),
              input_schema: input_schema,
              output_schema: output_schema,
              default_model: ctx.workflow.default_model
            )
            loop_nodes << node
            next
          end

          if match = line.match(/^\s*run\s+"([^"]+)"(.*)$/)
            ref = match[1]
            tail = match[2]? || ""
            params = parse_line_params(tail, ctx.workflow_file, "run #{ref}")
            runtime = params["runtime"]?.try { |value| parse_runtime_object(value, ctx.workflow_file) }
            env = params["env"]?.try { |value| parse_runtime_object(value, ctx.workflow_file) }
            input_schema = compile_optional_function_schema(params["input_schema"]?, ctx.workflow_file, "run #{ref}", "input")
            output_schema = compile_optional_function_schema(params["output_schema"]?, ctx.workflow_file, "run #{ref}", "output")
            run_params = extract_named_args(params, Set{"runtime", "env", "input_schema", "output_schema"}, ctx.workflow_file)

            loop_nodes << create_run_node(
              ref,
              runtime: runtime,
              env: env,
              params: run_params,
              input_schema: input_schema,
              output_schema: output_schema,
              workflow_root: ctx.workflow_root
            )
          end
        end

        return if loop_nodes.empty?

        loop_body = wrap_nodes_in_control(loop_nodes, "until-body")
        control_node = Cogni::Workflow::WorkflowNode.new("until-#{start_line}", Cogni::Workflow::NodeKind::Control) do |node_ctx|
          iterations = 0
          merged = {} of String => JSON::Any
          result = Cogni::Workflow::WorkflowNodeResult.continue

          while !evaluate_dsl_condition(condition, with_state(node_ctx, merged)) && iterations < 100
            iterations += 1
            result = loop_body.execute(with_state(node_ctx, merged))
            break if result.action != Cogni::Workflow::NodeAction::Continue.to_s.downcase
            if data = result.data
              data.each { |k, v| merged[k] = v }
            end
          end

          if result.action == Cogni::Workflow::NodeAction::Continue.to_s.downcase
            Cogni::Workflow::WorkflowNodeResult.continue(merged)
          else
            result
          end
        end
        ctx.workflow.step(control_node)
      end

      # Parse loop do...end block
      private def parse_loop_block(ctx : WorkflowParserContext, start_line : Int32, end_line : Int32) : Nil
        loop_nodes = [] of Cogni::Workflow::WorkflowNode

        i = start_line + 1
        while i <= end_line
          raw = ctx.lines[i]
          line = raw.strip
          i += 1

          next if line.empty? || line.starts_with?("#")
          next if line == "end"

          if match = line.match(/^\s*agent\s+"([^"]+)"(.*)$/)
            agent_id = match[1]
            tail = match[2]? || ""
            loaded = ctx.agent_index[agent_id]?
            params = parse_line_params(tail, ctx.workflow_file, "agent #{agent_id}")
            model = parse_optional_string(params["model"]?) || loaded.try(&.model)
            prompt = parse_optional_string(params["prompt"]?) || loaded.try(&.prompt)
            input_schema = resolve_agent_schema(
              params["input_schema"]?,
              loaded,
              kind: "input",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )
            output_schema = resolve_agent_schema(
              params["output_schema"]?,
              loaded,
              kind: "output",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )
            resume_schema = resolve_agent_schema(
              params["resume_schema"]?,
              loaded,
              kind: "resume",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )

            node = create_agent_node(
              agent_id,
              prompt: prompt,
              model: model,
              resume_schema: resume_schema,
              voice_config: loaded.try(&.voice_config),
              guardrails_config: loaded.try(&.guardrails_config),
              input_schema: input_schema,
              output_schema: output_schema,
              default_model: ctx.workflow.default_model
            )
            loop_nodes << node
            next
          end

          if match = line.match(/^\s*run\s+"([^"]+)"(.*)$/)
            ref = match[1]
            tail = match[2]? || ""
            params = parse_line_params(tail, ctx.workflow_file, "run #{ref}")
            runtime = params["runtime"]?.try { |value| parse_runtime_object(value, ctx.workflow_file) }
            env = params["env"]?.try { |value| parse_runtime_object(value, ctx.workflow_file) }
            input_schema = compile_optional_function_schema(params["input_schema"]?, ctx.workflow_file, "run #{ref}", "input")
            output_schema = compile_optional_function_schema(params["output_schema"]?, ctx.workflow_file, "run #{ref}", "output")
            run_params = extract_named_args(params, Set{"runtime", "env", "input_schema", "output_schema"}, ctx.workflow_file)

            loop_nodes << create_run_node(
              ref,
              runtime: runtime,
              env: env,
              params: run_params,
              input_schema: input_schema,
              output_schema: output_schema,
              workflow_root: ctx.workflow_root
            )
          end
        end

        return if loop_nodes.empty?

        loop_body = wrap_nodes_in_control(loop_nodes, "loop-body")
        control_node = Cogni::Workflow::WorkflowNode.new("loop-#{start_line}", Cogni::Workflow::NodeKind::Control) do |node_ctx|
          iterations = 0
          merged = {} of String => JSON::Any
          result = Cogni::Workflow::WorkflowNodeResult.continue

          while iterations < 100
            iterations += 1
            result = loop_body.execute(with_state(node_ctx, merged))
            break if result.action != Cogni::Workflow::NodeAction::Continue.to_s.downcase
            if data = result.data
              data.each { |k, v| merged[k] = v }
            end
          end

          if result.action == Cogni::Workflow::NodeAction::Continue.to_s.downcase
            Cogni::Workflow::WorkflowNodeResult.continue(merged)
          else
            result
          end
        end
        ctx.workflow.step(control_node)
      end

      # Create an agent node (used for parallel and conditional blocks)
      private def create_agent_node(
        id : String,
        prompt : String? = nil,
        model : String? = nil,
        resume_schema : Cogni::Workflows::DSL::Validator? = nil,
        voice_config : Cogni::Workflow::AnyHash? = nil,
        guardrails_config : Cogni::Workflow::AnyHash? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil,
        default_model : String? = nil
      ) : Cogni::Workflow::WorkflowNode
        builder = Cogni::Workflow::WorkflowDefinition.new("__registry_builder__")
        builder.use(model: default_model) if default_model
        Cogni::RegistryApi.build_node(
          builder,
          "agent",
          id,
          prompt: prompt,
          model: model,
          resume_schema: resume_schema,
          voice_config: voice_config,
          guardrails_config: guardrails_config,
          input_schema: input_schema,
          output_schema: output_schema,
        )
      end

      private def create_run_node(
        ref : String,
        runtime : Cogni::Workflow::AnyHash? = nil,
        env : Cogni::Workflow::AnyHash? = nil,
        params : Cogni::Workflow::AnyHash? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil,
        workflow_root : String? = nil
      ) : Cogni::Workflow::WorkflowNode
        builder = Cogni::Workflow::WorkflowDefinition.new("__registry_builder__")
        Cogni::RegistryApi.build_node(
          builder,
          "run",
          ref,
          runtime: runtime,
          env: env,
          params: params,
          workflow_root: workflow_root,
          input_schema: input_schema,
          output_schema: output_schema,
        )
      end

      # Wrap multiple nodes in a single control node
      private def wrap_nodes_in_control(nodes : Array(Cogni::Workflow::WorkflowNode), name : String) : Cogni::Workflow::WorkflowNode
        Cogni::Workflow::WorkflowNode.new(name, Cogni::Workflow::NodeKind::Control) do |ctx|
          merged = {} of String => JSON::Any
          halted = nil.as(Cogni::Workflow::WorkflowNodeResult?)
          nodes.each do |node|
            result = node.execute(Cogni::Workflow::NodeContext.new(
              workflow_id: ctx.workflow_id,
              run_id: ctx.run_id,
              node_id: node.id,
              input_data: ctx.input_data,
              state: ctx.state.merge(merged) { |_k, _left, right| right },
              init_data: ctx.init_data,
              node_results: ctx.node_results,
              runtime_context: ctx.runtime_context,
              request_context: ctx.request_context,
              trigger_data: ctx.trigger_data,
              resume_data: ctx.resume_data,
            ))
            if result.action != Cogni::Workflow::NodeAction::Continue.to_s.downcase
              halted = result
              break
            end
            if data = result.data
              data.each { |k, v| merged[k] = v }
            end
          end
          halted || Cogni::Workflow::WorkflowNodeResult.continue(merged)
        end
      end

      private def with_state(ctx : Cogni::Workflow::NodeContext, additions : Hash(String, JSON::Any)) : Cogni::Workflow::NodeContext
        Cogni::Workflow::NodeContext.new(
          workflow_id: ctx.workflow_id,
          run_id: ctx.run_id,
          node_id: ctx.node_id,
          input_data: ctx.input_data,
          state: ctx.state.merge(additions) { |_k, _left, right| right },
          init_data: ctx.init_data,
          node_results: ctx.node_results,
          runtime_context: ctx.runtime_context,
          request_context: ctx.request_context,
          trigger_data: ctx.trigger_data,
          resume_data: ctx.resume_data,
        )
      end

      private def evaluate_dsl_condition(expression : String, ctx : Cogni::Workflow::NodeContext) : Bool
        normalized = expression.strip
        return true if normalized == "true"
        return false if normalized == "false"

        if match = normalized.match(/^input\.([a-zA-Z_][a-zA-Z0-9_]*)\s*==\s*"([^"]*)"$/)
          actual = ctx.input_data[match[1]]?.try(&.as_s?) || ctx.state[match[1]]?.try(&.as_s?)
          return actual == match[2]
        end
        if match = normalized.match(/^input\.([a-zA-Z_][a-zA-Z0-9_]*)\s*!=\s*"([^"]*)"$/)
          actual = ctx.input_data[match[1]]?.try(&.as_s?) || ctx.state[match[1]]?.try(&.as_s?)
          return actual != match[2]
        end
        if match = normalized.match(/^state\.([a-zA-Z_][a-zA-Z0-9_]*)\s*==\s*"([^"]*)"$/)
          actual = ctx.state[match[1]]?.try(&.as_s?)
          return actual == match[2]
        end
        if match = normalized.match(/^state\.([a-zA-Z_][a-zA-Z0-9_]*)\s*!=\s*"([^"]*)"$/)
          actual = ctx.state[match[1]]?.try(&.as_s?)
          return actual != match[2]
        end
        if match = normalized.match(/^(input|state)\.([a-zA-Z_][a-zA-Z0-9_]*)\s*(>=|<=|>|<)\s*([0-9]+(?:\.[0-9]+)?)$/)
          source = match[1] == "input" ? ctx.input_data : ctx.state
          actual = source[match[2]]?.try(&.as_f?) || source[match[2]]?.try(&.as_i?).try(&.to_f)
          return false unless actual
          target = match[4].to_f
          op = match[3]
          return actual >= target if op == ">="
          return actual <= target if op == "<="
          return actual > target if op == ">"
          return actual < target if op == "<"
        end
        if match = normalized.match(/^input\.([a-zA-Z_][a-zA-Z0-9_]*)$/)
          value = ctx.input_data[match[1]]? || ctx.state[match[1]]?
          return value.try(&.raw) == true
        end
        if match = normalized.match(/^state\.([a-zA-Z_][a-zA-Z0-9_]*)$/)
          return ctx.state[match[1]]?.try(&.raw) == true
        end

        false
      end

      # Helper to build agent user prompt from context
      private def build_agent_user_prompt_from_ctx(ctx : Cogni::Workflow::NodeContext) : String
        if input = ctx.input_data["input"]?
          if as_text = input.as_s?
            return as_text
          end
          if hash = input.as_h?
            return hash["content"]?.try(&.as_s?) || hash["text"]?.try(&.as_s?) || input.to_json
          end
          return input.to_json
        end

        task = ctx.input_data["task"]?.try(&.as_s?) || ctx.state["task"]?.try(&.as_s?)
        return task if task

        prompt = ctx.input_data["prompt"]?.try(&.as_s?) || ctx.state["prompt"]?.try(&.as_s?)
        return prompt if prompt

        ctx.state.to_json
      end

      # Helper to resolve model from context
      private def resolve_model_from_ctx(ctx : Cogni::Workflow::NodeContext, agent_model : String?, default_model : String?) : String
        request_model = ctx.input_data["model"]?.try(&.as_s?) || ctx.state["model"]?.try(&.as_s?)
        return request_model if request_model
        return agent_model if agent_model
        ctx.state["workflow_model"]?.try(&.as_s?) || default_model || "openai/gpt-4.1-mini"
      end

      private def resolve_agent_schema(
        literal : String?,
        loaded : Agents::LoadedAgent?,
        kind : String,
        workflow_file : String,
        agent_id : String
      ) : Cogni::Workflows::DSL::Validator?
        if literal
          stripped = literal.strip
          if match = stripped.match(/^schema_ref\("([^"]+)"\)$/)
            ref_name = match[1]
            schema_source = case ref_name
                            when "input"
                              loaded.try(&.input_schema_dsl)
                            when "output"
                              loaded.try(&.output_schema_dsl)
                            when "resume"
                              loaded.try(&.resume_schema_dsl)
                            else
                              raise "#{workflow_file}: unknown schema_ref(\"#{ref_name}\") for agent #{agent_id}"
                            end
            raise "#{workflow_file}: schema_ref(\"#{ref_name}\") missing in agent #{agent_id} markdown" unless schema_source
            return Cogni::Workflows::DSL::CrystalDSL.compile(schema_source, "#{workflow_file}: agent #{agent_id} #{kind} schema_ref")
          end

          return Cogni::Workflows::DSL::CrystalDSL.compile(stripped, "#{workflow_file}: agent #{agent_id} #{kind} schema")
        end

        fallback = case kind
                   when "input"
                     loaded.try(&.input_schema_dsl)
                   when "output"
                     loaded.try(&.output_schema_dsl)
                   when "resume"
                     loaded.try(&.resume_schema_dsl)
                   else
                     nil
                   end
        return nil unless fallback
        Cogni::Workflows::DSL::CrystalDSL.compile(fallback, "#{workflow_file}: agent #{agent_id} #{kind} markdown schema")
      end

      private def resolve_suspend_resume_schema(
        literal : String?,
        ctx : WorkflowParserContext,
        suspend_id : String
      ) : Cogni::Workflows::DSL::Validator?
        return nil unless literal
        stripped = literal.strip

        if match = stripped.match(/^schema_ref\("([^"]+)"\)$/)
          ref_name = match[1]
          raise "#{ctx.workflow_file}: suspend #{suspend_id} only supports schema_ref(\"resume\")" unless ref_name == "resume"

          agent_id = ctx.last_agent_id
          raise "#{ctx.workflow_file}: suspend #{suspend_id} schema_ref(\"resume\") requires a preceding agent node" unless agent_id

          loaded = ctx.agent_index[agent_id]?
          schema_source = loaded.try(&.resume_schema_dsl)
          raise "#{ctx.workflow_file}: schema_ref(\"resume\") missing in agent #{agent_id} markdown" unless schema_source

          return Cogni::Workflows::DSL::CrystalDSL.compile(schema_source, "#{ctx.workflow_file}: suspend #{suspend_id} resume schema_ref")
        end

        Cogni::Workflows::DSL::CrystalDSL.compile(stripped, "#{ctx.workflow_file}: suspend #{suspend_id} resume schema")
      end

      private def parse_line_params(tail : String, workflow_file : String, context : String) : Hash(String, String)
        params = {} of String => String
        stripped = tail.strip
        return params if stripped.empty?

        working = stripped
        working = working[1..] if working.starts_with?(",")
        pieces = split_top_level_params(working)
        pieces.each do |piece|
          next if piece.strip.empty?
          separator = piece.index(':')
          raise "#{workflow_file}: invalid #{context} param '#{piece}'" unless separator
          key = piece[0, separator].strip
          value = piece[separator + 1, piece.size - separator - 1].strip
          raise "#{workflow_file}: invalid #{context} param '#{piece}'" if key.empty? || value.empty?
          params[key] = value
        end
        params
      end

      private def extract_named_args(params : Hash(String, String), skip_keys : Set(String), workflow_file : String) : Cogni::Workflow::AnyHash?
        args = {} of String => JSON::Any
        params.each do |key, value|
          next if skip_keys.includes?(key)
          args[key] = JSON.parse(value)
        rescue
          args[key] = parse_runtime_literal(value, workflow_file)
        end
        return nil if args.empty?
        args
      end

      private def parse_runtime_literal(literal : String, workflow_file : String) : JSON::Any
        stripped = literal.strip
        begin
          if stripped.starts_with?("{")
            return JSON.parse(parse_runtime_object(stripped, workflow_file).to_json)
          end
          if stripped.starts_with?("[")
            return JSON.parse(stripped)
          end
          JSON.parse(stripped)
        rescue
          if stripped.starts_with?("\"") && stripped.ends_with?("\"")
            return JSON.parse(stripped)
          end
          JSON.parse(stripped.to_json)
        end
      end

      private def compile_required_function_schema(
        literal : String?,
        workflow_file : String,
        fn_name : String,
        kind : String
      ) : Cogni::Workflows::DSL::Validator
        raise "#{workflow_file}: function #{fn_name} requires #{kind}_schema" unless literal
        stripped = literal.strip
        Cogni::Workflows::DSL::CrystalDSL.compile(stripped, "#{workflow_file}: function #{fn_name} #{kind} schema")
      end

      private def compile_optional_function_schema(
        literal : String?,
        workflow_file : String,
        fn_name : String,
        kind : String
      ) : Cogni::Workflows::DSL::Validator?
        return nil unless literal
        stripped = literal.strip
        Cogni::Workflows::DSL::CrystalDSL.compile(stripped, "#{workflow_file}: function #{fn_name} #{kind} schema")
      end

      private def ensure_output_schema_superset!(
        workflow_file : String,
        fn_name : String,
        input_schema : Cogni::Workflows::DSL::Validator,
        output_schema : Cogni::Workflows::DSL::Validator
      )
        Cogni::Workflows::DSL::Compatibility.ensure_output_superset!(input_schema, output_schema)
      rescue ex : Cogni::Workflows::DSL::ValidationError
        raise "#{workflow_file}: function #{fn_name} output_schema must cover input_schema: #{ex.message}"
      end

      private def split_top_level_params(value : String) : Array(String)
        parts = [] of String
        current = ""
        depth_paren = 0
        depth_brace = 0
        depth_bracket = 0
        in_string = false
        escaped = false

        value.each_char do |ch|
          if in_string
            current += ch.to_s
            if escaped
              escaped = false
            elsif ch == '\\'
              escaped = true
            elsif ch == '"'
              in_string = false
            end
            next
          end

          case ch
          when '"'
            in_string = true
            current += ch.to_s
          when '('
            depth_paren += 1
            current += ch.to_s
          when ')'
            depth_paren -= 1 if depth_paren > 0
            current += ch.to_s
          when '{'
            depth_brace += 1
            current += ch.to_s
          when '}'
            depth_brace -= 1 if depth_brace > 0
            current += ch.to_s
          when '['
            depth_bracket += 1
            current += ch.to_s
          when ']'
            depth_bracket -= 1 if depth_bracket > 0
            current += ch.to_s
          when ','
            if depth_paren == 0 && depth_brace == 0 && depth_bracket == 0
              token = current.strip
              parts << token unless token.empty?
              current = ""
            else
              current += ch.to_s
            end
          else
            current += ch.to_s
          end
        end

        token = current.strip
        parts << token unless token.empty?
        parts
      end

      private def collect_balanced_expression(
        initial : String,
        lines : Array(String),
        next_line : Int32,
        end_line : Int32,
        context : String,
        workflow_file : String
      ) : NamedTuple(value: String, next_index: Int32)
        expression = initial.strip
        index = next_line
        paren, brace, bracket = scan_structure_balance(expression)

        while (paren > 0 || brace > 0 || bracket > 0) && index < end_line
          continuation = lines[index].strip
          expression = "#{expression} #{continuation}"
          d_paren, d_brace, d_bracket = scan_structure_balance(continuation)
          paren += d_paren
          brace += d_brace
          bracket += d_bracket
          index += 1
        end

        if paren != 0 || brace != 0 || bracket != 0
          raise "#{workflow_file}: #{context} has unbalanced expression"
        end

        {value: expression, next_index: index}
      end

      private def scan_structure_balance(value : String) : Tuple(Int32, Int32, Int32)
        paren = 0
        brace = 0
        bracket = 0
        in_string = false
        escaped = false

        value.each_char do |ch|
          if in_string
            if escaped
              escaped = false
            elsif ch == '\\'
              escaped = true
            elsif ch == '"'
              in_string = false
            end
            next
          end

          case ch
          when '"'
            in_string = true
          when '('
            paren += 1
          when ')'
            paren -= 1
          when '{'
            brace += 1
          when '}'
            brace -= 1
          when '['
            bracket += 1
          when ']'
            bracket -= 1
          end
        end

        {paren, brace, bracket}
      end

      private def parse_optional_string(literal : String?) : String?
        return nil unless literal
        return nil unless literal.starts_with?('"') && literal.ends_with?('"') && literal.size >= 2
        literal[1, literal.size - 2]
      end

      private def parse_runtime_object(literal : String, workflow_file : String) : Cogni::Workflow::AnyHash
        parsed = YAML.parse(literal)
        hash = JSON.parse(parsed.to_json).as_h?
        raise "#{workflow_file}: runtime must be an object: #{literal}" unless hash
        hash
      rescue ex
        raise "#{workflow_file}: invalid runtime object '#{literal}': #{ex.message}"
      end

      # Parse Resources annotation body: model: "...", skill: ["..."], tool: ["..."]
      private def parse_resources_annotation_params(content : String) : NamedTuple(model: String?, skill: (String | Array(String))?, tool: (String | Array(String))?)

        model = nil.as(String?)
        skill = nil.as((String | Array(String))?)
        tool = nil.as((String | Array(String))?)

        # Parse model: "..."
        if match = content.match(/model:\s*"([^"]+)"/)
          model = match[1]
        end

        # Parse skill: "..." or skill: ["...", "..."]
        if match = content.match(/skill:\s*\[([^\]]*)\]/)
          # Array syntax
          arr_content = match[1]
          skills = parse_string_array(arr_content)
          skill = skills unless skills.empty?
        elsif match = content.match(/skill:\s*"([^"]+)"/)
          # Single string syntax
          skill = match[1]
        end

        # Parse tool: "..." or tool: ["...", "..."]
        if match = content.match(/tool:\s*\[([^\]]*)\]/)
          # Array syntax
          arr_content = match[1]
          tools = parse_string_array(arr_content)
          tool = tools unless tools.empty?
        elsif match = content.match(/tool:\s*"([^"]+)"/)
          # Single string syntax
          tool = match[1]
        end

        {model: model, skill: skill, tool: tool}
      end

      private def parse_string_array(content : String) : Array(String)
        result = [] of String
        content.scan(/"([^"]+)"/) do |match|
          result << match[1]
        end
        result
      end

      private def openapi_document : String
        {
          "openapi" => "3.0.3",
          "info" => {
            "title" => "CogniCore API",
            "version" => CogniCore::VERSION,
            "description" => "Current HTTP API surface with scaffolded workflow endpoints.",
          },
          "servers" => [
            {"url" => "http://localhost:#{@port}"},
          ],
          "tags" => [
            {"name" => "System"},
            {"name" => "Workflows"},
            {"name" => "Tools"},
            {"name" => "Skills"},
            {"name" => "Runs"},
            {"name" => "HITL"},
            {"name" => "Compat"},
          ],
          "paths" => {
            "/health" => {
              "get" => {
                "tags" => ["System"],
                "summary" => "Health check",
                "responses" => {
                  "200" => {
                    "description" => "Server health",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/HealthResponse"},
                      },
                    },
                  },
                },
              },
            },
            "/v1/workflows" => {
              "get" => {
                "tags" => ["Workflows"],
                "summary" => "List workflow IDs",
                "responses" => {
                  "200" => {
                    "description" => "Workflow id list",
                    "content" => {
                      "application/json" => {
                        "schema" => {
                          "type" => "array",
                          "items" => {"type" => "string"},
                        },
                      },
                    },
                  },
                },
              },
            },
            "/v1/workflows/{workflowId}" => {
              "get" => {
                "tags" => ["Workflows"],
                "summary" => "Get workflow metadata",
                "parameters" => [
                  {
                    "name" => "workflowId",
                    "in" => "path",
                    "required" => true,
                    "schema" => {"type" => "string"},
                  },
                ],
                "responses" => {
                  "200" => {
                    "description" => "Workflow metadata",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/WorkflowResponse"},
                      },
                    },
                  },
                  "404" => {"$ref" => "#/components/responses/NotFound"},
                },
              },
            },
            "/v1/tools" => {
              "get" => {
                "tags" => ["Tools"],
                "summary" => "List discovered tools",
                "responses" => {
                  "200" => {
                    "description" => "Tool list",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/ToolListResponse"},
                      },
                    },
                  },
                },
              },
            },
            "/v1/mcp/servers" => {
              "get" => {
                "tags" => ["MCP"],
                "summary" => "List configured MCP servers",
                "responses" => {"200" => {"description" => "MCP server list"}},
              },
              "post" => {
                "tags" => ["MCP"],
                "summary" => "Create MCP server",
                "responses" => {"200" => {"description" => "MCP server"}},
              },
            },
            "/v1/mcp/servers/{serverId}" => {
              "get" => {
                "tags" => ["MCP"],
                "summary" => "Get MCP server",
                "responses" => {"200" => {"description" => "MCP server"}, "404" => {"$ref" => "#/components/responses/NotFound"}},
              },
              "patch" => {
                "tags" => ["MCP"],
                "summary" => "Update MCP server",
                "responses" => {"200" => {"description" => "MCP server"}},
              },
              "delete" => {
                "tags" => ["MCP"],
                "summary" => "Delete MCP server",
                "responses" => {"204" => {"description" => "Deleted"}, "404" => {"$ref" => "#/components/responses/NotFound"}},
              },
            },
            "/v1/mcp/servers/{serverId}/reconnect" => {
              "post" => {
                "tags" => ["MCP"],
                "summary" => "Reconnect MCP server",
                "responses" => {"200" => {"description" => "MCP server"}},
              },
            },
            "/v1/mcp/catalog" => {
              "get" => {
                "tags" => ["MCP"],
                "summary" => "List full MCP catalog",
                "responses" => {"200" => {"description" => "MCP catalog"}},
              },
            },
            "/v1/mcp/catalog/tools" => {
              "get" => {
                "tags" => ["MCP"],
                "summary" => "List MCP tools",
                "responses" => {"200" => {"description" => "MCP tool catalog"}},
              },
            },
            "/v1/mcp/catalog/resources" => {
              "get" => {
                "tags" => ["MCP"],
                "summary" => "List MCP resources",
                "responses" => {"200" => {"description" => "MCP resource catalog"}},
              },
            },
            "/v1/mcp/catalog/prompts" => {
              "get" => {
                "tags" => ["MCP"],
                "summary" => "List MCP prompts",
                "responses" => {"200" => {"description" => "MCP prompt catalog"}},
              },
            },
            "/mcp" => {
              "post" => {
                "tags" => ["MCP"],
                "summary" => "MCP JSON-RPC endpoint",
                "responses" => {"200" => {"description" => "JSON-RPC response"}},
              },
            },
            "/v1/skills" => {
              "get" => {
                "tags" => ["Skills"],
                "summary" => "List discovered skills",
                "responses" => {
                  "200" => {
                    "description" => "Skill list",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/SkillListResponse"},
                      },
                    },
                  },
                },
              },
            },
            "/v1/skills/{skillId}" => {
              "get" => {
                "tags" => ["Skills"],
                "summary" => "Get skill metadata",
                "parameters" => [
                  {
                    "name" => "skillId",
                    "in" => "path",
                    "required" => true,
                    "schema" => {"type" => "string"},
                  },
                ],
                "responses" => {
                  "200" => {
                    "description" => "Skill metadata",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/SkillItem"},
                      },
                    },
                  },
                  "404" => {"$ref" => "#/components/responses/NotFound"},
                },
              },
            },
            "/v1/skills/{skillId}/execute" => {
              "post" => {
                "tags" => ["Skills"],
                "summary" => "Execute skill (scaffold)",
                "parameters" => [
                  {
                    "name" => "skillId",
                    "in" => "path",
                    "required" => true,
                    "schema" => {"type" => "string"},
                  },
                ],
                "responses" => {
                  "200" => {
                    "description" => "Skill execution response",
                    "content" => {
                      "application/json" => {
                        "schema" => {"type" => "object"},
                      },
                    },
                  },
                  "404" => {"$ref" => "#/components/responses/NotFound"},
                },
              },
            },
            "/v1/responses" => {
              "post" => {
                "tags" => ["Compat"],
                "summary" => "OpenAI responses compatibility route",
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/chat/completions" => {
              "post" => {
                "tags" => ["Compat"],
                "summary" => "OpenAI chat completions compatibility route",
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/workflows/{workflowId}/runs" => {
              "post" => {
                "tags" => ["Runs"],
                "summary" => "Start workflow run (scaffold)",
                "parameters" => [
                  {
                    "name" => "workflowId",
                    "in" => "path",
                    "required" => true,
                    "schema" => {"type" => "string"},
                  },
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
              "get" => {
                "tags" => ["Runs"],
                "summary" => "List runs for workflow",
                "parameters" => [
                  {
                    "name" => "workflowId",
                    "in" => "path",
                    "required" => true,
                    "schema" => {"type" => "string"},
                  },
                ],
                "responses" => {
                  "200" => {
                    "description" => "Run id list",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/RunListResponse"},
                      },
                    },
                  },
                },
              },
            },
            "/v1/workflows/{workflowId}/runs/{runId}" => {
              "get" => {
                "tags" => ["Runs"],
                "summary" => "Get run snapshot (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/workflows/{workflowId}/runs/{runId}/resume" => {
              "post" => {
                "tags" => ["Runs"],
                "summary" => "Resume run (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/workflows/{workflowId}/runs/{runId}/restart" => {
              "post" => {
                "tags" => ["Runs"],
                "summary" => "Restart run (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/workflows/{workflowId}/runs/{runId}/time-travel" => {
              "post" => {
                "tags" => ["Runs"],
                "summary" => "Time travel run (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/workflows/{workflowId}/runs/{runId}/cancel" => {
              "post" => {
                "tags" => ["Runs"],
                "summary" => "Cancel run (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/hitl/runs" => {
              "get" => {
                "tags" => ["HITL"],
                "summary" => "List HITL runs",
                "responses" => {
                  "200" => {
                    "description" => "Run id list",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/RunListResponse"},
                      },
                    },
                  },
                },
              },
            },
            "/v1/hitl/runs/{workflowId}/{runId}" => {
              "get" => {
                "tags" => ["HITL"],
                "summary" => "Get HITL run details (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/hitl/runs/{workflowId}/{runId}/actions" => {
              "post" => {
                "tags" => ["HITL"],
                "summary" => "Apply HITL action (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
          },
          "components" => {
            "parameters" => {
              "WorkflowId" => {
                "name" => "workflowId",
                "in" => "path",
                "required" => true,
                "schema" => {"type" => "string"},
              },
              "RunId" => {
                "name" => "runId",
                "in" => "path",
                "required" => true,
                "schema" => {"type" => "string"},
              },
            },
            "responses" => {
              "NotImplemented" => {
                "description" => "Endpoint scaffold is not implemented yet",
                "content" => {
                  "application/json" => {
                    "schema" => {"$ref" => "#/components/schemas/ErrorEnvelope"},
                    "example" => {
                      "error" => {
                        "type" => "not_implemented",
                        "message" => "endpoint pending implementation",
                      },
                    },
                  },
                },
              },
              "NotFound" => {
                "description" => "Resource not found",
                "content" => {
                  "application/json" => {
                    "schema" => {"$ref" => "#/components/schemas/ErrorEnvelope"},
                  },
                },
              },
            },
            "schemas" => {
              "HealthResponse" => {
                "type" => "object",
                "required" => ["status", "timestamp"],
                "properties" => {
                  "status" => {"type" => "string", "example" => "ok"},
                  "timestamp" => {"type" => "string"},
                },
              },
              "WorkflowResponse" => {
                "type" => "object",
                "required" => ["workflow_id", "source_root_type", "workflow_file", "agents", "skills", "tools"],
                "properties" => {
                  "workflow_id" => {"type" => "string"},
                  "source_root_type" => {"type" => "string"},
                  "workflow_file" => {"type" => "string"},
                  "agents" => {"type" => "array", "items" => {"type" => "string"}},
                  "skills" => {"type" => "array", "items" => {"type" => "string"}},
                  "tools" => {"type" => "array", "items" => {"type" => "string"}},
                  "default_model" => {"type" => "string", "nullable" => true},
                },
              },
              "ToolItem" => {
                "type" => "object",
                "required" => ["id", "workflow_id"],
                "properties" => {
                  "id" => {"type" => "string"},
                  "workflow_id" => {"type" => "string"},
                },
              },
              "ToolListResponse" => {
                "type" => "object",
                "required" => ["tools"],
                "properties" => {
                  "tools" => {"type" => "array", "items" => {"$ref" => "#/components/schemas/ToolItem"}},
                },
              },
              "SkillItem" => {
                "type" => "object",
                "required" => ["id", "workflow_id", "name", "description", "file_path"],
                "properties" => {
                  "id" => {"type" => "string"},
                  "workflow_id" => {"type" => "string"},
                  "name" => {"type" => "string"},
                  "description" => {"type" => "string"},
                  "file_path" => {"type" => "string"},
                },
              },
              "SkillListResponse" => {
                "type" => "object",
                "required" => ["skills"],
                "properties" => {
                  "skills" => {"type" => "array", "items" => {"$ref" => "#/components/schemas/SkillItem"}},
                },
              },
              "RunListResponse" => {
                "type" => "object",
                "required" => ["runs"],
                "properties" => {
                  "runs" => {"type" => "array", "items" => {"type" => "string"}},
                },
              },
              "ErrorEnvelope" => {
                "type" => "object",
                "required" => ["error"],
                "properties" => {
                  "error" => {
                    "type" => "object",
                    "required" => ["type", "message"],
                    "properties" => {
                      "type" => {"type" => "string"},
                      "message" => {"type" => "string"},
                    },
                  },
                },
              },
            },
          },
        }.to_json
      end

      private def swagger_ui_html : String
        <<-HTML
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <title>CogniCore API Docs</title>
            <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
          </head>
          <body>
            <div id="swagger-ui"></div>
            <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
            <script>
              window.ui = SwaggerUIBundle({
                url: "/openapi.json",
                dom_id: "#swagger-ui"
              });
            </script>
          </body>
        </html>
        HTML
      end
    end
  end
end
