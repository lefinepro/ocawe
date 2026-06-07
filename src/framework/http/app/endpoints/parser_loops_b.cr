module ACD
  module Kemal
    class App
      private def parse_loop_block(ctx : WorkflowParserContext, start_line : Int32, end_line : Int32) : Nil
        loop_nodes = [] of Ocawe::Workflow::WorkflowNode

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
            attributes = parse_line_attributes(tail, ctx.workflow_file, "agent #{agent_id}")
            model = parse_optional_string(attributes["model"]?) || loaded.try(&.model)
            prompt = parse_optional_string(attributes["prompt"]?) || loaded.try(&.prompt)
            input_schema = resolve_agent_schema(
              attributes["input_schema"]?,
              loaded,
              kind: "input",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )
            output_schema = resolve_agent_schema(
              attributes["output_schema"]?,
              loaded,
              kind: "output",
              workflow_file: ctx.workflow_file,
              agent_id: agent_id
            )
            resume_schema = resolve_agent_schema(
              attributes["resume_schema"]?,
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
              output_schema: output_schema
            )
            loop_nodes << node
            next
          end

          if match = line.match(/^\s*exec\s+"([^"]+)"(.*)$/)
            ref = match[1]
            tail = match[2]? || ""
            attributes = parse_line_attributes(tail, ctx.workflow_file, "exec #{ref}")
            runtime = attributes["runtime"]?.try { |value| parse_runtime_object(value, ctx.workflow_file) }
            env = attributes["env"]?.try { |value| parse_runtime_object(value, ctx.workflow_file) }
            input_schema = compile_optional_function_schema(attributes["input_schema"]?, ctx.workflow_file, "exec #{ref}", "input")
            output_schema = compile_optional_function_schema(attributes["output_schema"]?, ctx.workflow_file, "exec #{ref}", "output")
            exec_attributes = extract_attributes(attributes, Set{"runtime", "env", "input_schema", "output_schema"}, ctx.workflow_file)

            loop_nodes << create_exec_node(
              ref,
              runtime: runtime,
              env: env,
              attributes: exec_attributes,
              input_schema: input_schema,
              output_schema: output_schema,
              workflow_root: ctx.workflow_root
            )
            next
          end

          if match = line.match(/^([a-z][a-z0-9_]*)(.*)$/)
            node_kind = match[1]
            tail = match[2]? || ""
            attributes = parse_line_attributes(tail, ctx.workflow_file, "node #{node_kind}")
            input_schema = compile_optional_function_schema(attributes["input_schema"]?, ctx.workflow_file, "node #{node_kind}", "input")
            output_schema = compile_optional_function_schema(attributes["output_schema"]?, ctx.workflow_file, "node #{node_kind}", "output")
            node_attributes = extract_attributes(attributes, Set{"input_schema", "output_schema"}, ctx.workflow_file)
            loop_nodes << create_internal_node(
              node_kind,
              node_kind,
              attributes: node_attributes,
              input_schema: input_schema,
              output_schema: output_schema
            )
          end
        end

        return if loop_nodes.empty?

        loop_body = wrap_nodes_in_control(loop_nodes, "loop-body")
        control_node = Ocawe::Workflow::WorkflowNode.new("loop-#{start_line}", Ocawe::Workflow::NodeKind::Control) do |node_ctx|
          iterations = 0
          merged = {} of String => JSON::Any
          result = Ocawe::Workflow::WorkflowNodeResult.continue

          while iterations < 100
            iterations += 1
            result = loop_body.execute(with_state(node_ctx, merged))
            break if result.action != Ocawe::Workflow::NodeAction::Continue.to_s.downcase
            if data = result.data
              data.each { |k, v| merged[k] = v }
            end
          end

          if result.action == Ocawe::Workflow::NodeAction::Continue.to_s.downcase
            Ocawe::Workflow::WorkflowNodeResult.continue(merged)
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
        resume_schema : Ocawe::Workflows::DSL::Validator? = nil,
        voice_config : Ocawe::Workflow::AnyHash? = nil,
        guardrails_config : Ocawe::Workflow::AnyHash? = nil,
        input_schema : Ocawe::Workflows::DSL::Validator? = nil,
        output_schema : Ocawe::Workflows::DSL::Validator? = nil
      ) : Ocawe::Workflow::WorkflowNode
        builder = Ocawe::Workflow::WorkflowDefinition.new("__registry_builder__")
        Ocawe::RegistryApi.build_node(
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

      private def create_exec_node(
        ref : String,
        runtime : Ocawe::Workflow::AnyHash? = nil,
        env : Ocawe::Workflow::AnyHash? = nil,
        attributes : Ocawe::Workflow::AnyHash? = nil,
        input_schema : Ocawe::Workflows::DSL::Validator? = nil,
        output_schema : Ocawe::Workflows::DSL::Validator? = nil,
        workflow_root : String? = nil
      ) : Ocawe::Workflow::WorkflowNode
        raise "exec requires runtime for non-mcp refs: #{ref}" if runtime.nil? && !ref.starts_with?("mcp:")

        builder = Ocawe::Workflow::WorkflowDefinition.new("__registry_builder__")
        Ocawe::RegistryApi.build_node(
          builder,
          "exec",
          ref,
          runtime: runtime,
          env: env,
          attributes: attributes,
          workflow_root: workflow_root,
          input_schema: input_schema,
          output_schema: output_schema,
        )
      end

      private def create_internal_node(
        node_kind : String,
        id : String,
        attributes : Ocawe::Workflow::AnyHash? = nil,
        input_schema : Ocawe::Workflows::DSL::Validator? = nil,
        output_schema : Ocawe::Workflows::DSL::Validator? = nil
      ) : Ocawe::Workflow::WorkflowNode
        builder = Ocawe::Workflow::WorkflowDefinition.new("__registry_builder__")
        Ocawe::RegistryApi.build_node(
          builder,
          "node_kind",
          id,
          node_kind_name: node_kind,
          node_kind_attributes: attributes || ({} of String => JSON::Any),
          input_schema: input_schema,
          output_schema: output_schema,
        )
      end
    end
  end
end
