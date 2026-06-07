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

      private def json_body(env) : Ocawe::Workflow::AnyHash
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

      private def load_workflow_definition(bundle : Discovery::WorkflowBundle, loaded_agents : Array(Agents::LoadedAgent)) : Ocawe::Workflow::WorkflowDefinition
        workflow = Ocawe::Workflow.create_workflow(bundle.id, "Loaded from #{bundle.workflow_file}")
        agent_index = {} of String => Agents::LoadedAgent
        loaded_agents.each { |agent| agent_index[agent.id] = agent }

        if cawfile = bundle.cawfile
          load_cawfile_workflow(workflow, bundle, cawfile, agent_index)
        elsif File.extname(bundle.workflow_file) == ".cr"
          lines = File.read_lines(bundle.workflow_file)
          ctx = WorkflowParserContext.new(
            workflow: workflow,
            agent_index: agent_index,
            workflow_file: bundle.workflow_file,
            workflow_root: bundle.root_path,
            lines: lines,
            dataset_service: @dataset_service
          )
          parse_workflow_body(ctx, 0, lines.size)
        else
          raise "#{bundle.workflow_file}: unsupported workflow file format"
        end

        workflow.commit
        enforce_enabled_node_kinds!(workflow, bundle.workflow_file)
        workflow
      end

      private def rcl_value_to_json_any(value : RCL::Value) : JSON::Any
        case value
        when String
          JSON.parse(value.to_json)
        when Int32, Int64, Float64, Bool, Nil
          JSON.parse(value.to_json)
        when Array(RCL::Value)
          JSON.parse(value.map { |v| rcl_value_to_json_any(v) }.to_json)
        when Hash(String, RCL::Value)
          JSON.parse(value.transform_values { |v| rcl_value_to_json_any(v) }.to_json)
        else
          JSON.parse("null")
        end
      end

      private def load_cawfile_workflow(
        workflow : Ocawe::Workflow::WorkflowDefinition,
        bundle : Discovery::WorkflowBundle,
        cawfile : Discovery::CawfileBundle,
        agent_index : Hash(String, Agents::LoadedAgent)
      )
        # Register Cawfile agents into index so parser can reference them
        cawfile.agents.each do |agent_spec|
          agent_index[agent_spec.id] = Agents::LoadedAgent.new(
            id: agent_spec.id,
            prompt: agent_spec.prompt || "",
            model: agent_spec.model,
            description: agent_spec.description || "",
            file_path: bundle.workflow_file,
            voice_config: agent_spec.voice_config.try { |h| h.transform_values { |v| JSON.parse(v.to_json) } } || {} of String => JSON::Any,
            guardrails_config: agent_spec.guardrails_config.try { |h| h.transform_values { |v| JSON.parse(v.to_json) } } || {} of String => JSON::Any,
          )
        end

        # Load Cawfile keys as workspace annotations
        unless cawfile.keys.empty?
          workspace = {} of String => JSON::Any
          cawfile.keys.each do |key_spec|
            workspace["key_#{key_spec.name}"] = JSON.parse({
              "required"    => key_spec.required,
              "description" => key_spec.description,
              "provider"    => key_spec.provider,
            }.to_json)
          end
          workflow.workspace(workspace)
        end

        if File.extname(bundle.workflow_file) == ".cr"
          lines = File.read_lines(bundle.workflow_file)
          ctx = WorkflowParserContext.new(
            workflow: workflow,
            agent_index: agent_index,
            workflow_file: bundle.workflow_file,
            workflow_root: bundle.root_path,
            lines: lines,
            dataset_service: @dataset_service
          )
          parse_workflow_body(ctx, 0, lines.size)
        elsif cawfile.workflow_steps.empty?
          raise "#{bundle.workflow_file}: Cawfile has no workflow steps and no .acd.cr fallback"
        else
          cawfile.workflow_steps.each do |step|
            case step.type
            when "agent"
              agent_id = step.id
              loaded = agent_index[agent_id]?
              attrs = step.params
              workflow.agent(
                agent_id,
                prompt: loaded.try(&.prompt),
                model: loaded.try(&.model),
                input_schema: nil,
                output_schema: nil,
              )
            when "skill"
              workflow.skill(step.id, agent: nil)
            when "exec"
              workflow.exec(
                step.id,
                runtime: step.params["runtime"]?.try { |v| rcl_value_to_json_any(v).as_h? },
                env: step.params["env"]?.try { |v| rcl_value_to_json_any(v).as_h? },
                workflow_root: bundle.root_path,
              )
            when "suspend"
              workflow.suspend(step.id, reason: step.params["reason"]?.try { |v| v.is_a?(String) ? v : v.to_s } || "human input required")
            when "rag"
              workflow.rag(step.id, config: step.params["config"]?.try { |v| rcl_value_to_json_any(v).as_h? } || {} of String => JSON::Any)
            when "voice"
              workflow.voice(step.id, config: step.params["config"]?.try { |v| rcl_value_to_json_any(v).as_h? } || {} of String => JSON::Any)
            when "control", "node_kind"
              workflow.step("node_kind", step.id,
                node_kind_name: step.params["kind"]?.try { |v| v.is_a?(String) ? v : v.to_s } || step.id,
                node_kind_attributes: step.params.reject { |k, _| k == "kind" }.transform_values { |v| rcl_value_to_json_any(v) },
              )
            else
              workflow.step("node_kind", step.id,
                node_kind_name: step.type,
                node_kind_attributes: step.params.transform_values { |v| rcl_value_to_json_any(v) },
              )
            end
          end
        end
      end

      private def enforce_enabled_node_kinds!(workflow : Ocawe::Workflow::WorkflowDefinition, workflow_file : String) : Nil
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
        getter workflow : Ocawe::Workflow::WorkflowDefinition
        getter agent_index : Hash(String, Agents::LoadedAgent)
        getter workflow_file : String
        getter workflow_root : String
        getter lines : Array(String)
        getter dataset_service : Ocawe::Dataset::Service
        property last_agent_id : String?

        def initialize(
          @workflow : Ocawe::Workflow::WorkflowDefinition,
          @agent_index : Hash(String, Agents::LoadedAgent),
          @workflow_file : String,
          @workflow_root : String,
          @lines : Array(String),
          @dataset_service : Ocawe::Dataset::Service
        )
          @last_agent_id = nil
        end
      end
    end
  end
end
