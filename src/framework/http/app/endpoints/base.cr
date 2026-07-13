require "set"

module ACD
  module Kemal
    class App
      RELOAD_INTERVAL_SECONDS = 2.0
      @aptok_federation : Aptok::Federation?
      @federation_kv : Aptok::KvStore

      def initialize(
        @port : Int32,
        @settings : Ocawe::Config::Settings = Ocawe::Config::Settings.default,
      )
        @locator = Discovery::WorkflowLocator.new(Dir.current)
        @agent_loader = Agents::Loader.new
        @skill_loader = Skills::Loader.new
        @workflow_engine = Ocawe::Workflow::Engine.new
        @workflow_service = Ocawe::Workflow::Service.new(@workflow_engine)
        @dataset_service = Ocawe::Dataset::Service.new(build_dataset_store(@settings.datasets))
        @aptok_federation = nil.as(Aptok::Federation?)
        @federation_kv = Aptok::MemoryKvStore.new
        @mcp_manager = Ocawe::MCP.manager
        @workflow_ids = [] of String
        @service_workflow_ids = [] of String
        @started_service_workflows = Set(String).new
        @workflow_index = {} of String => NamedTuple(
          source_root_type: String,
          workflow_file: String,
          agents: Array(String),
          skills: Array(String),
          tools: Array(String),
          default_model: String?,
          logger: Ocawe::Workflow::AnyHash?,
          node_loggers: Hash(String, Ocawe::Workflow::AnyHash),
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
        Ocawe::Telemetry.configure(@settings.telemetry)
        start_telemetry_exporter
        @mcp_manager.configure(@settings.mcp)
        register_configured_functions!
        reload_cache!
        start_service_workflows
        start_reload_watcher

        ::Kemal.config.port = @port
        ::Kemal.config.add_handler(Ocawe::Telemetry::HTTPHandler.new) if Ocawe::Telemetry.enabled?
        mount_health_endpoints
        mount_docs_endpoints
        unless @settings.api.federation_only?
          mount_workflow_endpoints
          mount_agent_endpoints
          mount_tool_endpoints
          mount_skill_endpoints
          mount_dataset_endpoints
          mount_run_endpoints
          mount_hitl_endpoints
          mount_compat_endpoints
          mount_models_endpoints
          mount_environments_endpoints
          mount_trigger_endpoints
          mount_mcp_endpoints
          mount_mcp_server_endpoint
          mount_keys_endpoints
        end
        if federation_api_enabled?
          mount_federation_endpoints
          bootstrap_federation_subscriptions
          start_federation_poller
        end

        ::Kemal.run(trap_signal: false)
      end

      private def federation_api_enabled? : Bool
        @settings.api.enable?("federation") ||
          !@settings.federation.auto_subscribe.empty? ||
          Ocawe::Workflow.function_registry.registered?("ocawe_handle_aptok_inbox_activity")
      end

      private def start_telemetry_exporter : Nil
        return unless Ocawe::Telemetry.enabled?

        spawn do
          loop do
            sleep 10.seconds
            Ocawe::Telemetry.flush
          end
        end
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
              start_service_workflows
              fingerprint = current
              puts "[ocawecore] workflow cache reloaded"
            rescue ex
              STDERR.puts "[ocawecore] workflow cache reload failed: #{ex.message}"
            end
          end
        end
      end

      private def reload_cache!
        bundles = @locator.list_workflows
        @dataset_service.reset_dsl_sources!
        rebuilt_engine = Ocawe::Workflow::Engine.new
        ids = [] of String
        index = {} of String => NamedTuple(
          source_root_type: String,
          workflow_file: String,
          agents: Array(String),
          skills: Array(String),
          tools: Array(String),
          default_model: String?,
          logger: Ocawe::Workflow::AnyHash?,
          node_loggers: Hash(String, Ocawe::Workflow::AnyHash),
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
        service_workflow_ids = [] of String
        global_agents = @agent_loader.load_dir("./agents")

        bundles.each do |bundle|
          loaded_agents = merge_agents(global_agents, @agent_loader.load_dir(bundle.agents_dir))
          loaded_skills = @skill_loader.load_dir(bundle.skills_dir)

          ids << bundle.id
          service_workflow_ids << bundle.id if bundle.service
          definition = load_workflow_definition(bundle, loaded_agents)
          rebuilt_engine.register(definition)
          tool_ids = [] of String
          definition.nodes.each do |node|
            next unless node.kind == Ocawe::Workflow::NodeKind::Exec
            next unless node.metadata["runtime"]?
            tool_ids << node.id unless tool_ids.includes?(node.id)
          end

          loaded_skills.each do |skill|
            qualified_id = "#{bundle.id}:#{skill.id}"
            skills_index[qualified_id] = {
              id:          qualified_id,
              workflow_id: bundle.id,
              name:        skill.name,
              description: skill.description,
              file_path:   skill.file_path,
            }
          end

          loaded_agents.each do |agent|
            qualified_id = "#{bundle.id}:#{agent.id}"
            agents_index[qualified_id] = {
              id:            qualified_id,
              workflow_id:   bundle.id,
              name:          agent.id,
              description:   agent.description,
              prompt:        agent.prompt,
              model:         agent.model,
              default_model: definition.default_model,
              file_path:     agent.file_path,
            }
          end

          tool_ids.each do |tool_id|
            tools_index << {
              id:          tool_id,
              workflow_id: bundle.id,
            }
          end

          index[bundle.id] = {
            source_root_type: bundle.source_root_type,
            workflow_file:    bundle.workflow_file,
            agents:           loaded_agents.map(&.id),
            skills:           loaded_skills.map(&.id),
            tools:            tool_ids,
            default_model:    definition.default_model,
            logger:           definition.default_logger,
            node_loggers:     definition.node_loggers,
          }
        end

        @cache_lock.synchronize do
          @workflow_ids = ids
          @service_workflow_ids = service_workflow_ids
          @workflow_index = index
          @skills_index = skills_index
          @agents_index = agents_index
          @tools_index = tools_index
          @workflow_engine = rebuilt_engine
          @workflow_service = Ocawe::Workflow::Service.new(@workflow_engine)
        end
      end

      private def start_service_workflows : Nil
        workflow_ids = @cache_lock.synchronize { @service_workflow_ids.dup }

        workflow_ids.each do |workflow_id|
          already_started = @cache_lock.synchronize do
            if @started_service_workflows.includes?(workflow_id)
              true
            else
              @started_service_workflows << workflow_id
              false
            end
          end
          next if already_started

          spawn do
            run_id = "service-#{workflow_id}"
            input_data = {
              "service"     => JSON.parse(true.to_json),
              "workflow_id" => JSON.parse(workflow_id.to_json),
            } of String => JSON::Any

            begin
              @workflow_service.start_run(workflow_id, run_id: run_id, input_data: input_data)
              @cache_lock.synchronize { @started_service_workflows.delete(workflow_id) }
              STDERR.puts "[ocawecore] service workflow exited: #{workflow_id}"
            rescue ex
              @cache_lock.synchronize { @started_service_workflows.delete(workflow_id) }
              STDERR.puts "[ocawecore] service workflow failed: #{workflow_id}: #{ex.message || ex.class.name}"
            end
          end
        end
      end

      private def workflow_ids : Array(String)
        @cache_lock.synchronize { @workflow_ids.dup }
      end

      private def workflow_by_id(workflow_id : String)
        @cache_lock.synchronize { @workflow_index[workflow_id]? }
      end

      private def workflows : Array(NamedTuple(id: String, name: String, description: String, default_model: String?, agents: Array(String), skills: Array(String), tools: Array(String)))
        @cache_lock.synchronize do
          @workflow_index.map do |id, w|
            {
              id:            id,
              name:          id,
              description:   w[:source_root_type],
              default_model: w[:default_model],
              agents:        w[:agents],
              skills:        w[:skills],
              tools:         w[:tools],
            }
          end
        end
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
        local_agents : Array(ACD::Agents::LoadedAgent),
      ) : Array(ACD::Agents::LoadedAgent)
        merged = {} of String => ACD::Agents::LoadedAgent
        global_agents.each { |agent| merged[agent.id] = agent }
        local_agents.each { |agent| merged[agent.id] = agent }
        merged.values.to_a
      end

      private def register_configured_functions! : Nil
        config = @settings
        Ocawe::RegistryApi.reset_all!

        config.functions.each do |name, handler|
          Ocawe::RegistryApi.register_system_function(name, &handler)
        end
        config.workspace_bootstrap.try(&.call)
      end

      private def build_dataset_store(config : Ocawe::Config::DatasetSettings) : Ocawe::Dataset::Store::Base
        case config.adapter.strip.downcase
        when "", "memory"
          Ocawe::Dataset::Store::InMemory.new
        when "file"
          Ocawe::Dataset::Store::File.new(config.file_root)
        when "sqlite", "sqlite3"
          Ocawe::Dataset::Store::SQLite.new(config.file_root)
        else
          raise "unsupported dataset adapter: #{config.adapter}"
        end
      end
    end
  end
end
