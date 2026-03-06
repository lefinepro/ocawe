module ACD
  module Kemal
    class App
      private def parse_workflow_body(ctx : WorkflowParserContext, start_line : Int32, end_line : Int32) : Int32
        exec_pattern = /^\s*exec\s+"([^"]+)"(.*)$/
        skill_pattern = /^\s*skill\s+"([^"]+)"(?:\s*,\s*agent:\s*"([^"]+)")?/
        rag_pattern = /^\s*rag\s+"([^"]+)"(?:\s*,\s*config:\s*(\{.*\}))?/
        suspend_pattern = /^\s*suspend\s+"([^"]+)"(.*)$/
        reserved_keywords = Set{
          "workflow", "do", "end", "struct", "class", "module",
          "include", "extend", "getter", "setter", "property",
          "alias", "enum", "lib", "fun", "require",
          "agent", "skill", "exec", "voice", "rag", "suspend", "dataset",
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
              raise "#{ctx.workflow_file}: `custom_fn` is not supported for agent. Use internal node calls (`function_name`)."
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
          if line.match(/^\s*@\[Workspace\(/)
            workspace_annotation = line
            unless workspace_annotation.includes?(")]")
              while i < end_line
                continuation = ctx.lines[i].strip
                workspace_annotation = "#{workspace_annotation} #{continuation}"
                i += 1
                break if continuation.includes?(")]")
              end
            end

            match = workspace_annotation.match(/^\s*@\[Workspace\((.*)\)\]\s*$/)
            raise "#{ctx.workflow_file}: invalid Workspace annotation syntax '#{workspace_annotation}'" unless match

            parsed = parse_workspace_annotation_params(match[1], ctx.workflow_file)
            workspace_scope_any = parsed.delete("scope")
            workspace_scope = workspace_scope_any.try(&.as_s?)
            case workspace_scope
            when "workflow"
              ctx.workflow.workspace(parsed)
            when "node", "next"
              ctx.workflow.workspace_next(parsed)
            when nil
              if ctx.workflow.nodes.empty?
                ctx.workflow.workspace(parsed)
              else
                ctx.workflow.workspace_next(parsed)
              end
            else
              raise "#{ctx.workflow_file}: Workspace scope must be workflow|node|next"
            end
            next
          end
          if line.match(/^\s*@resources\s+/)
            raise "#{ctx.workflow_file}: `@resources` is not a Crystal annotation. Use `@[Resources(model: \"...\", skill: [...], tool: [...])]`."
          end
          if line.match(/^\s*docker\s+use\s+/)
            raise "#{ctx.workflow_file}: `docker use` is deprecated. Use `@[Workspace(...)]`."
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
          if match = line.match(exec_pattern)
            ref = match[1]
            tail = match[2]? || ""
            params = parse_line_params(tail, ctx.workflow_file, "exec #{ref}")
            runtime = params["runtime"]?.try { |value| parse_runtime_object(value, ctx.workflow_file) }
            env = params["env"]?.try { |value| parse_runtime_object(value, ctx.workflow_file) }
            input_schema = compile_optional_function_schema(params["input_schema"]?, ctx.workflow_file, "exec #{ref}", "input")
            output_schema = compile_optional_function_schema(params["output_schema"]?, ctx.workflow_file, "exec #{ref}", "output")
            exec_params = extract_named_args(params, Set{"runtime", "env", "input_schema", "output_schema"}, ctx.workflow_file)

            raise "#{ctx.workflow_file}: exec #{ref} requires runtime for non-mcp refs" if runtime.nil? && !ref.starts_with?("mcp:")
            ctx.workflow.exec(
              ref,
              runtime: runtime,
              env: env,
              workflow_root: ctx.workflow_root,
              params: exec_params,
              input_schema: input_schema,
              output_schema: output_schema,
            )
            next
          end
          if line.starts_with?("tool ")
            raise "#{ctx.workflow_file}: `tool` is removed from DSL. Use `exec \"path_or_inline\", runtime: {...}` for external tools, or internal node calls (`function_name`)."
          end
          if line.match(/^\s*run\s+"([^"]+)"(.*)$/)
            raise "#{ctx.workflow_file}: `run` is removed. Use `exec` for external tools and internal node calls (`function_name`)."
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
            tail = match[2]? || ""
            params = parse_line_params(tail, ctx.workflow_file, "node #{fn_name}")
            input_schema = compile_optional_function_schema(params["input_schema"]?, ctx.workflow_file, "node #{fn_name}", "input")
            output_schema = compile_optional_function_schema(params["output_schema"]?, ctx.workflow_file, "node #{fn_name}", "output")
            node_params = extract_named_args(params, Set{"input_schema", "output_schema"}, ctx.workflow_file)
            ctx.workflow.step(
              "node_kind",
              fn_name,
              node_kind_name: fn_name,
              node_kind_parameters: node_params || ({} of String => JSON::Any),
              input_schema: input_schema,
              output_schema: output_schema,
            )
            next
          end
        end

        i
      end
    end
  end
end
