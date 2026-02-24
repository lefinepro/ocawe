module ACD
  module HTTP
    class App
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
    end
  end
end
