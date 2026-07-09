module Ocawe
  module Workflow
    class WorkflowDefinition
      private def append_node(node : WorkflowNode) : self
        ensure_not_committed!
        resolved_workspace = resolve_workspace_for_node(node, @pending_node_workspace)
        if resolved_workspace
          node.metadata["workspace"] = JSON.parse(resolved_workspace.to_json)
          @node_workspaces[node.id] = resolved_workspace
        end
        @pending_node_workspace = nil
        @nodes << node
        self
      end

      private def resolve_workspace_for_node(node : WorkflowNode, inline_override : AnyHash?) : AnyHash?
        merged = ({} of String => JSON::Any)
        if workflow_default = @default_workspace
          workflow_default.each { |k, v| merged[k] = v }
        end

        if existing = node.metadata["workspace"]?.try(&.as_h?)
          existing.each { |k, v| merged[k] = v }
        end

        if inline_override
          inline_override.each { |k, v| merged[k] = v }
        end

        return nil if merged.empty?
        Ocawe::Workflow.workspace_registry.resolve(merged)
      end

      private def normalize_hash(hash : AnyHash) : AnyHash
        JSON.parse(hash.to_json).as_h
      end

      private def ensure_not_committed!
        raise "workflow '#{@id}' already committed" if @committed
      end

      private def next_node_counter : Int32
        @next_node_id += 1
        @next_node_id
      end

      private def with_context_for(ctx : NodeContext, node : WorkflowNode)
        NodeContext.new(
          workflow_id: ctx.workflow_id,
          run_id: ctx.run_id,
          node_id: node.id,
          input_data: ctx.input_data,
          state: ctx.state,
          init_data: ctx.init_data,
          node_results: ctx.node_results,
          runtime_context: ctx.runtime_context,
          request_context: ctx.request_context,
          trigger_data: ctx.trigger_data,
          resume_data: ctx.resume_data,
        )
      end

      private def with_isolated_state_context(ctx : NodeContext, node : WorkflowNode)
        # Creates a context with a deep-copied state to prevent cross-node mutation in parallel branches
        NodeContext.new(
          workflow_id: ctx.workflow_id,
          run_id: ctx.run_id,
          node_id: node.id,
          input_data: ctx.input_data,
          state: ctx.state.dup,
          init_data: ctx.init_data,
          node_results: ctx.node_results.dup,
          runtime_context: ctx.runtime_context,
          request_context: ctx.request_context,
          trigger_data: ctx.trigger_data,
          resume_data: ctx.resume_data,
        )
      end

      private def wrap_nodes_in_control(nodes : Array(WorkflowNode), name : String) : WorkflowNode
        WorkflowNode.new(name, NodeKind::Control) do |ctx|
          merged = {} of String => JSON::Any
          failed = nil.as(WorkflowNodeResult?)
          nodes.each do |node|
            result = node.execute(with_state(ctx, merged, node.id))
            if result.action != NodeAction::Continue.to_s.downcase
              failed = result
              break
            end
            if data = result.data
              enriched = data.dup
              enriched["step"] = JSON.parse(node.id.to_json)
              ctx.node_results[node.id] = enriched
              data.each { |k, v| merged[k] = v }
            end
          end
          failed || WorkflowNodeResult.continue(merged)
        end
      end

      private def with_state(ctx : NodeContext, additions : AnyHash, node_id : String? = nil) : NodeContext
        NodeContext.new(
          workflow_id: ctx.workflow_id,
          run_id: ctx.run_id,
          node_id: node_id || ctx.node_id,
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

      private def evaluate_condition(expression : String, ctx : NodeContext) : Bool
        normalized = expression.strip
        return true if normalized == "true"
        return false if normalized == "false"

        if match = normalized.match(/^(.+?)\s*(==|!=|>=|<=|>|<)\s*(.+)$/)
          left = resolve_condition_value(match[1], ctx)
          right = parse_condition_literal(match[3], ctx)
          return compare_condition_values(left, right, match[2])
        end

        if value = resolve_condition_value(normalized, ctx)
          return truthy_condition_value(value)
        end

        false
      end

      private def parse_condition_literal(value : String, ctx : NodeContext) : JSON::Any?
        stripped = value.strip
        if resolved = resolve_condition_value(stripped, ctx)
          return resolved
        end
        return JSON.parse(stripped) if stripped.starts_with?('"') || stripped == "true" || stripped == "false" || stripped == "null"
        return JSON.parse(stripped) if stripped.match(/^-?\d+(?:\.\d+)?$/)
        JSON.parse(stripped.to_json)
      rescue
        JSON.parse(stripped.to_json)
      end

      private def resolve_condition_value(path : String, ctx : NodeContext) : JSON::Any?
        normalized = path.strip
        if match = normalized.match(/^step\["([^"]+)"\](.*)$/)
          value = ctx.node_results[match[1]]?.try { |result| JSON.parse(result.to_json) }
          return follow_condition_path(value, match[2])
        end
        if match = normalized.match(/^(input|state)\.(.+)$/)
          source = match[1] == "input" ? ctx.input_data : ctx.state
          first, rest = split_condition_path_segment(match[2])
          return follow_condition_path(source[first]?, rest)
        end
        nil
      end

      private def compare_condition_values(left : JSON::Any?, right : JSON::Any?, op : String) : Bool
        return op == "!=" if left.nil? || right.nil?

        if left_number = condition_number(left)
          if right_number = condition_number(right)
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

      private def condition_number(value : JSON::Any) : Float64?
        value.as_f? || value.as_i?.try(&.to_f)
      end

      private def truthy_condition_value(value : JSON::Any) : Bool
        raw = value.raw
        return raw if raw.is_a?(Bool)
        return !raw.empty? if raw.is_a?(String)
        return raw != 0 if raw.is_a?(Int64)
        return raw != 0.0 if raw.is_a?(Float64)
        !raw.nil?
      end

      private def split_condition_path_segment(path : String) : Tuple(String, String)
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

      private def follow_condition_path(value : JSON::Any?, path : String) : JSON::Any?
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

      private def resolve_model(ctx : NodeContext, agent_model : String?) : String
        request_model = ctx.input_data["model"]?.try(&.as_s?) || ctx.state["model"]?.try(&.as_s?)
        return request_model if request_model
        return agent_model if agent_model
        ctx.state["workflow_model"]?.try(&.as_s?) || @default_model || "openai/gpt-4.1-mini"
      end

      private def run_voice_node(ctx : NodeContext, config : AnyHash) : AnyHash
        effective_config = (ctx.state["active_voice"]?.try(&.as_h?) || ({} of String => JSON::Any)).dup
        config.each { |k, v| effective_config[k] = v }

        voice_operator = effective_config["voice_operator"]?.try(&.as_s?) || effective_config["provider"]?.try(&.as_s?) || "default"
        speaker = effective_config["speaker"]?.try(&.as_s?)

        audio = ctx.state["audio"]?.try(&.as_s?) || ctx.input_data["audio"]?.try(&.as_s?) || ""
        text = ctx.state["text"]?.try(&.as_s?) || ctx.input_data["text"]?.try(&.as_s?) || ""

        resolved_text = if text.empty?
                          audio.empty? ? "[voice-node:no-input]" : "transcribed: #{audio}"
                        else
                          text
                        end

        payload = {
          "voice_status" => JSON.parse("ok".to_json),
          "voice_operator" => JSON.parse(voice_operator.to_json),
          "text" => JSON.parse(resolved_text.to_json),
          "audio_url" => JSON.parse("memory://voice/#{ctx.run_id}/output.wav".to_json),
        } of String => JSON::Any

        payload["speaker"] = JSON.parse(speaker.to_json) if speaker
        payload["active_voice"] = JSON.parse(effective_config.to_json) unless effective_config.empty?
        payload
      end

      private def run_rag_node(ctx : NodeContext, config : AnyHash) : AnyHash
        RagRuntime.execute(ctx, config)
      end

      private def build_agent_user_prompt(ctx : NodeContext) : String
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
    end
  end
end
