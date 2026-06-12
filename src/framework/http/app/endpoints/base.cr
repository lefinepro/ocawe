module ACD
  module Kemal
    class App
      RELOAD_INTERVAL_SECONDS = 2.0
      @aptok_federation : Aptok::Federation?
      @federation_kv : Aptok::KvStore

      def initialize(
        @port : Int32,
        workflows_root : String? = nil,
        @settings : Ocawe::Config::Settings = Ocawe::Config::Settings.default
      )
        config = @settings.workflows
        preferred_root = workflows_root || config.preferred_workflows_root
        @locator = Discovery::WorkflowLocator.new(preferred_root)
        @agent_loader = Agents::Loader.new
        @skill_loader = Skills::Loader.new
        @workflow_engine = Ocawe::Workflow::Engine.new
        @workflow_service = Ocawe::Workflow::Service.new(@workflow_engine)
        @dataset_service = Ocawe::Dataset::Service.new(build_dataset_store(@settings.datasets))
        @aptok_federation = nil.as(Aptok::Federation?)
        @federation_kv = Aptok::MemoryKvStore.new
        @mcp_manager = Ocawe::MCP.manager
        @workflow_ids = [] of String
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
        @mcp_manager.configure(@settings.mcp)
        register_configured_functions!
        reload_cache!
        start_reload_watcher

        ::Kemal.config.port = @port
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
          mount_trigger_endpoints
          mount_mcp_endpoints
          mount_mcp_server_endpoint
          mount_keys_endpoints
        end
        mount_federation_endpoints if @settings.api.enable?("federation")
        bootstrap_federation_subscriptions if @settings.api.enable?("federation")
        start_federation_poller if @settings.api.enable?("federation")

        ::Kemal.run(trap_signal: false)
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
        global_agents = @agent_loader.load_dir("./agents")

        bundles.each do |bundle|
          loaded_agents = merge_agents(global_agents, @agent_loader.load_dir(bundle.agents_dir))
          loaded_skills = @skill_loader.load_dir(bundle.skills_dir)

          ids << bundle.id
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
          @workflow_index = index
          @skills_index = skills_index
          @agents_index = agents_index
          @tools_index = tools_index
          @workflow_engine = rebuilt_engine
          @workflow_service = Ocawe::Workflow::Service.new(@workflow_engine)
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
        else
          raise "unsupported dataset adapter: #{config.adapter}"
        end
      end
    end
  end
end
