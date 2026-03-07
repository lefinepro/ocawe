module Cogni
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
        Cogni::Workflow.workspace_registry.resolve(merged)
      end

      private def normalize_hash(hash : AnyHash) : AnyHash
        JSON.parse(hash.to_json).as_h
      end

      private def ensure_not_committed!
        raise "workflow '#{@id}' already committed" if @committed
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

        if match = normalized.match(/^input\.([a-zA-Z_][a-zA-Z0-9_]*)$/)
          value = ctx.input_data[match[1]]? || ctx.state[match[1]]?
          return value.try(&.raw) == true
        end
        if match = normalized.match(/^state\.([a-zA-Z_][a-zA-Z0-9_]*)$/)
          return ctx.state[match[1]]?.try(&.raw) == true
        end

        false
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
