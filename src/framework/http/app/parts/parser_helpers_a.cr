module ACD
  module HTTP
    class App
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
    end
  end
end
