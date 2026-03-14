module ACD
  module Kemal
    class App
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
        json_error(env, 501, "not_implemented", message)
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
          return json_error(env, 404, "not_found", message)
        end
        if message.includes?("unknown node") || message.includes?("requires node")
          return json_error(env, 400, "bad_request", message)
        end
        return json_error(env, 422, "workflow_error", message)
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
    end
  end
end
