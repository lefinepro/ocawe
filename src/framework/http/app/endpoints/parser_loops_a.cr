module ACD
  module Kemal
    class App
      private def parse_while_block(ctx : WorkflowParserContext, start_line : Int32, end_line : Int32) : Nil
        raw = ctx.lines[start_line]
        line = raw.strip

        # Extract condition from "while <condition> do"
        match = line.match(/^\s*while\s+(.+)\s+do\s*$/)
        return unless match
        condition = match[1].strip

        loop_nodes = [] of Ocawe::Workflow::WorkflowNode

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

          if match = line.match(/^\s*(get|post|put)\s+"([^"]+)"(.*)$/)
            method = match[1]
            url = match[2]
            attributes = parse_line_attributes(match[3]? || "", ctx.workflow_file, "#{method} #{url}")
            loop_nodes << create_api_node(method, url, attributes, ctx.workflow_file)
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

        loop_body = wrap_nodes_in_control(loop_nodes, "while-body")
        control_node = Ocawe::Workflow::WorkflowNode.new("while-#{start_line}", Ocawe::Workflow::NodeKind::Control) do |node_ctx|
          iterations = 0
          merged = {} of String => JSON::Any
          result = Ocawe::Workflow::WorkflowNodeResult.continue

          while evaluate_dsl_condition(condition, with_state(node_ctx, merged)) && iterations < 100
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

      # Parse until condition do...end loop
      private def parse_until_block(ctx : WorkflowParserContext, start_line : Int32, end_line : Int32) : Nil
        raw = ctx.lines[start_line]
        line = raw.strip

        # Extract condition from "until <condition> do"
        match = line.match(/^\s*until\s+(.+)\s+do\s*$/)
        return unless match
        condition = match[1].strip

        loop_nodes = [] of Ocawe::Workflow::WorkflowNode

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

          if match = line.match(/^\s*(get|post|put)\s+"([^"]+)"(.*)$/)
            method = match[1]
            url = match[2]
            attributes = parse_line_attributes(match[3]? || "", ctx.workflow_file, "#{method} #{url}")
            loop_nodes << create_api_node(method, url, attributes, ctx.workflow_file)
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

        loop_body = wrap_nodes_in_control(loop_nodes, "until-body")
        control_node = Ocawe::Workflow::WorkflowNode.new("until-#{start_line}", Ocawe::Workflow::NodeKind::Control) do |node_ctx|
          iterations = 0
          merged = {} of String => JSON::Any
          result = Ocawe::Workflow::WorkflowNodeResult.continue

          while !evaluate_dsl_condition(condition, with_state(node_ctx, merged)) && iterations < 100
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
    end
  end
end
