module ACD
  module Kemal
    class App
      private def wrap_nodes_in_control(nodes : Array(Ocawe::Workflow::WorkflowNode), name : String) : Ocawe::Workflow::WorkflowNode
        Ocawe::Workflow::WorkflowNode.new(name, Ocawe::Workflow::NodeKind::Control) do |ctx|
          merged = {} of String => JSON::Any
          halted = nil.as(Ocawe::Workflow::WorkflowNodeResult?)
          nodes.each do |node|
            result = node.execute(Ocawe::Workflow::NodeContext.new(
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
            if result.action != Ocawe::Workflow::NodeAction::Continue.to_s.downcase
              halted = result
              break
            end
            if data = result.data
              enriched = data.dup
              enriched["step"] = JSON.parse(node.id.to_json)
              ctx.node_results[node.id] = enriched
              data.each { |k, v| merged[k] = v }
            end
          end
          halted || Ocawe::Workflow::WorkflowNodeResult.continue(merged)
        end
      end

      private def with_state(ctx : Ocawe::Workflow::NodeContext, additions : Hash(String, JSON::Any)) : Ocawe::Workflow::NodeContext
        Ocawe::Workflow::NodeContext.new(
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

      private def evaluate_dsl_condition(expression : String, ctx : Ocawe::Workflow::NodeContext) : Bool
        normalized = expression.strip
        return true if normalized == "true"
        return false if normalized == "false"

        if match = normalized.match(/^(.+?)\s*(==|!=|>=|<=|>|<)\s*(.+)$/)
          left = resolve_dsl_condition_value(match[1], ctx)
          right = parse_dsl_condition_literal(match[3], ctx)
          return compare_dsl_condition_values(left, right, match[2])
        end

        if value = resolve_dsl_condition_value(normalized, ctx)
          return truthy_dsl_condition_value(value)
        end

        false
      end

      private def parse_dsl_condition_literal(value : String, ctx : Ocawe::Workflow::NodeContext) : JSON::Any?
        stripped = value.strip
        if resolved = resolve_dsl_condition_value(stripped, ctx)
          return resolved
        end
        return JSON.parse(stripped) if stripped.starts_with?('"') || stripped == "true" || stripped == "false" || stripped == "null"
        return JSON.parse(stripped) if stripped.match(/^-?\d+(?:\.\d+)?$/)
        JSON.parse(stripped.to_json)
      rescue
        JSON.parse(stripped.to_json)
      end

      private def resolve_dsl_condition_value(path : String, ctx : Ocawe::Workflow::NodeContext) : JSON::Any?
        normalized = path.strip
        if match = normalized.match(/^step\["([^"]+)"\](.*)$/)
          value = ctx.node_results[match[1]]?.try { |result| JSON.parse(result.to_json) }
          return follow_dsl_condition_path(value, match[2])
        end
        if match = normalized.match(/^(input|state)\.(.+)$/)
          source = match[1] == "input" ? ctx.input_data : ctx.state
          first, rest = split_dsl_condition_path_segment(match[2])
          return follow_dsl_condition_path(source[first]?, rest)
        end
        nil
      end

      private def compare_dsl_condition_values(left : JSON::Any?, right : JSON::Any?, op : String) : Bool
        return op == "!=" if left.nil? || right.nil?

        if left_number = dsl_condition_number(left)
          if right_number = dsl_condition_number(right)
            return left_number == right_number if op == "=="
            return left_number != right_number if op == "!="
            return left_number >= right_number if op == ">="
            return left_number <= right_number if op == "<="
            return left_number > right_number if op == ">"
            return left_number < right_number if op == "<"
          end
        end

        left_raw = left.raw
        right_raw = right.raw
        return left_raw == right_raw if op == "=="
        return left_raw != right_raw if op == "!="
        false
      end

      private def dsl_condition_number(value : JSON::Any) : Float64?
        value.as_f? || value.as_i?.try(&.to_f)
      end

      private def truthy_dsl_condition_value(value : JSON::Any) : Bool
        raw = value.raw
        return raw if raw.is_a?(Bool)
        return !raw.empty? if raw.is_a?(String)
        return raw != 0 if raw.is_a?(Int64)
        return raw != 0.0 if raw.is_a?(Float64)
        !raw.nil?
      end

      private def split_dsl_condition_path_segment(path : String) : Tuple(String, String)
        dot = path.index('.')
        bracket = path.index('[')
        idx = if dot && bracket
                Math.min(dot, bracket)
              else
                dot || bracket
              end
        return {path, ""} unless idx
        {path[0, idx], path[idx, path.size - idx]}
      end

      private def follow_dsl_condition_path(value : JSON::Any?, path : String) : JSON::Any?
        current = value
        remaining = path
        while current && !remaining.empty?
          if match = remaining.match(/^\.(\w+)(.*)$/)
            hash = current.as_h?
            return nil unless hash
            current = hash[match[1]]?
            remaining = match[2]
          elsif match = remaining.match(/^\[(\d+)\](.*)$/)
            array = current.as_a?
            return nil unless array
            current = array[match[1].to_i]?
            remaining = match[2]
          elsif match = remaining.match(/^\["([^"]+)"\](.*)$/)
            hash = current.as_h?
            return nil unless hash
            current = hash[match[1]]?
            remaining = match[2]
          else
            return nil
          end
        end
        current
      end

      # Helper to build agent user prompt from context
      private def build_agent_user_prompt_from_ctx(ctx : Ocawe::Workflow::NodeContext) : String
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
      private def resolve_model_from_ctx(ctx : Ocawe::Workflow::NodeContext, agent_model : String?, default_model : String?) : String
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
      ) : Ocawe::Workflows::DSL::Validator?
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
            return Ocawe::Workflows::DSL::CrystalDSL.compile(schema_source, "#{workflow_file}: agent #{agent_id} #{kind} schema_ref")
          end

          return Ocawe::Workflows::DSL::CrystalDSL.compile(stripped, "#{workflow_file}: agent #{agent_id} #{kind} schema")
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
        Ocawe::Workflows::DSL::CrystalDSL.compile(fallback, "#{workflow_file}: agent #{agent_id} #{kind} markdown schema")
      end

      private def resolve_suspend_resume_schema(
        literal : String?,
        ctx : WorkflowParserContext,
        suspend_id : String
      ) : Ocawe::Workflows::DSL::Validator?
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

          return Ocawe::Workflows::DSL::CrystalDSL.compile(schema_source, "#{ctx.workflow_file}: suspend #{suspend_id} resume schema_ref")
        end

        Ocawe::Workflows::DSL::CrystalDSL.compile(stripped, "#{ctx.workflow_file}: suspend #{suspend_id} resume schema")
      end

      private def parse_line_attributes(tail : String, workflow_file : String, context : String) : Hash(String, String)
        attributes = {} of String => String
        stripped = tail.strip
        return attributes if stripped.empty?

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
          attributes[key] = value
        end
        attributes
      end

      private def extract_attributes(attributes : Hash(String, String), skip_keys : Set(String), workflow_file : String) : Ocawe::Workflow::AnyHash?
        args = {} of String => JSON::Any
        attributes.each do |key, value|
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
