module ACD
  module Kemal
    class App
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
            parallel_nodes << node
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
            parallel_nodes << create_exec_node(
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
            parallel_nodes << create_internal_node(
              node_kind,
              node_kind,
              attributes: node_attributes,
              input_schema: input_schema,
              output_schema: output_schema
            )
            next
          end
        end

        # Add the parallel node to the workflow
        ctx.workflow.parallel(parallel_nodes) unless parallel_nodes.empty?
      end
    end
  end
end
