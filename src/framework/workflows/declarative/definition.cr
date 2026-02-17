require "../../cognicore/ai/client"

module Cogni
  module Workflows
    module Declarative
    class WorkflowDefinition
      getter id : String
      getter description : String?
      getter nodes : Array(WorkflowNode)
      getter default_model : String?
      getter default_skills : Array(String)
      getter default_tools : Array(String)

      def initialize(@id : String, @description : String? = nil)
        @nodes = [] of WorkflowNode
        @committed = false
        @default_model = nil
        @default_skills = [] of String
        @default_tools = [] of String
        @resource_scope_stack = [] of ResourceScope
      end

      # Unified resource defaults for model, skills, and tools
      # Supports: model: "...", skill: ["..."], tool: ["..."]
      def use(
        model : String? = nil,
        skill : (String | Array(String))? = nil,
        tool : (String | Array(String))? = nil
      ) : self
        ensure_not_committed!

        if model
          normalized = model.strip
          raise "use requires non-empty model string" if normalized.empty?
          @default_model = normalized
        end

        if skill
          skills = normalize_to_array(skill)
          skills.each do |s|
            @default_skills << s unless @default_skills.includes?(s)
          end
        end

        if tool
          tools = normalize_to_array(tool)
          tools.each do |t|
            @default_tools << t unless @default_tools.includes?(t)
          end
        end

        self
      end

      # Block-scoped resource defaults
      # Applies resources only within the block, then restores previous state
      def use(
        model : String? = nil,
        skill : (String | Array(String))? = nil,
        tool : (String | Array(String))? = nil,
        &block
      ) : self
        ensure_not_committed!

        # Save current state
        previous_model = @default_model
        previous_skills = @default_skills.dup
        previous_tools = @default_tools.dup

        # Push new scope
        scope = ResourceScope.new(
          model: model,
          skills: skill ? normalize_to_array(skill) : nil,
          tools: tool ? normalize_to_array(tool) : nil
        )
        @resource_scope_stack << scope

        # Apply scoped resources
        @default_model = model if model
        if skill
          normalize_to_array(skill).each do |s|
            @default_skills << s unless @default_skills.includes?(s)
          end
        end
        if tool
          normalize_to_array(tool).each do |t|
            @default_tools << t unless @default_tools.includes?(t)
          end
        end

        # Execute block
        block.call

        # Restore previous state
        @resource_scope_stack.pop
        @default_model = previous_model
        @default_skills = previous_skills
        @default_tools = previous_tools

        self
      end

      private def normalize_to_array(value : String | Array(String)) : Array(String)
        case value
        when String
          [value]
        when Array(String)
          value
        else
          [] of String
        end
      end

      def run(
        ref : String,
        runtime : AnyHash? = nil,
        env : AnyHash? = nil,
        workflow_root : String? = nil,
        params : AnyHash? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        metadata = {} of String => JSON::Any
        metadata["runtime"] = JSON.parse(runtime.to_json) if runtime
        metadata["env"] = JSON.parse(env.to_json) if env
        metadata["workflow_root"] = JSON.parse(workflow_root.to_json) if workflow_root
        metadata["params"] = JSON.parse(params.to_json) if params

        executor = RunExecutor.new
        append_node(WorkflowNode.new(ref, NodeKind::Run, metadata: metadata, input_schema: input_schema, output_schema: output_schema) do |ctx|
          WorkflowNodeResult.continue(executor.run(ref, ctx, runtime: runtime, env: env, workflow_root: workflow_root))
        end)
      end

      # Low-level chaining for explicit workflow nodes (used by control-flow internals).
      def step(node : WorkflowNode) : self
        append_node(node)
      end

      def agent(
        id : String,
        prompt : String? = nil,
        model : String? = nil,
        resume_schema : Cogni::Workflows::DSL::Validator? = nil,
        voice_config : AnyHash? = nil,
        guardrails_config : AnyHash? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        metadata = {} of String => JSON::Any
        metadata["has_resume_schema"] = JSON.parse(true.to_json) if resume_schema

        append_node(WorkflowNode.new(id, NodeKind::Agent, metadata: metadata, input_schema: input_schema, output_schema: output_schema) do |ctx|
          user_prompt = build_agent_user_prompt(ctx)
          Guardrails.validate_input!(id, user_prompt, guardrails_config)

          resolved_model = resolve_model(ctx, model)
          system_prompt = prompt || "You are agent #{id}."
          response = CogniCore::AI::Client.new.generate_text(
            model_spec: resolved_model,
            prompt: user_prompt,
            system: system_prompt,
            metadata: {
              "workflow_id" => JSON.parse(ctx.workflow_id.to_json),
              "run_id" => JSON.parse(ctx.run_id.to_json),
              "node_id" => JSON.parse(ctx.node_id.to_json),
              "agent_id" => JSON.parse(id.to_json),
            },
          )
          agent_result = AgentResult.new(
            agent_type: "default-agent",
            content: response.text,
            provider: response.provider,
            model: "#{response.provider}/#{response.model}",
          )

          Guardrails.validate_output!(id, agent_result.content, guardrails_config)

          outputs = ctx.state["agent_outputs"]?.try(&.as_h?) || {} of String => JSON::Any
          outputs = outputs.dup
          outputs[id] = JSON.parse(agent_result.to_any_hash.to_json)

          result = {
            "agent_outputs" => JSON.parse(outputs.to_json),
            "agent_result" => JSON.parse(agent_result.to_any_hash.to_json),
            "last_agent" => JSON.parse(id.to_json),
            "last_model" => JSON.parse((agent_result.model || "").to_json),
            "last_response" => JSON.parse(agent_result.content.to_json),
            "active_agent" => JSON.parse(id.to_json),
          } of String => JSON::Any

          if voice = voice_config
            result["active_voice"] = JSON.parse(voice.to_json)
          end

          WorkflowNodeResult.continue(result)
        end)
      end

      def step(
        kind : Cogni::NodeKind,
        id : String? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        node_id = id || "#{kind.node}-#{@nodes.size}"
        metadata = {
          "custom_node_kind" => JSON.parse(kind.node.to_json),
          "parameters" => JSON.parse(kind.parameters.to_json),
        } of String => JSON::Any

        append_node(WorkflowNode.new(node_id, NodeKind::Custom, metadata: metadata, input_schema: input_schema, output_schema: output_schema) do |ctx|
          raw = Cogni::Workflows::Declarative.node_kind_registry.call(kind.node, ctx, kind.parameters)
          case raw
          when WorkflowNodeResult
            raw
          when Hash(String, JSON::Any)
            WorkflowNodeResult.continue(raw)
          else
            raise "unsupported custom node kind result for #{kind.node}"
          end
        end)
      end


      def skill(
        id : String,
        agent_id : String? = nil,
        agent : String? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        meta = {} of String => JSON::Any
        selected_agent = agent || agent_id
        meta["agent_id"] = JSON.parse(selected_agent.to_json) if selected_agent
        append_node(WorkflowNode.new(id, NodeKind::Skill, metadata: meta, input_schema: input_schema, output_schema: output_schema) { |_ctx| WorkflowNodeResult.continue })
      end

      # Voice node implemented as first-class DSL behavior.
      # This keeps voice orchestration inside workflow DSL instead of auto-started tools.
      def voice(
        id : String,
        config : AnyHash = {} of String => JSON::Any,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        append_node(WorkflowNode.new(id, NodeKind::Voice, metadata: {
          "dsl_kind" => JSON.parse("voice".to_json),
          "config" => JSON.parse(config.to_json),
        } of String => JSON::Any, input_schema: input_schema, output_schema: output_schema) do |ctx|
          WorkflowNodeResult.continue(run_voice_node(ctx, config))
        end)
      end

      # RAG node implemented as first-class DSL behavior.
      # This keeps retrieval/memory orchestration inside workflow DSL.
      def rag(
        id : String,
        config : AnyHash = {} of String => JSON::Any,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        append_node(WorkflowNode.new(id, NodeKind::Rag, metadata: {
          "dsl_kind" => JSON.parse("rag".to_json),
          "config" => JSON.parse(config.to_json),
        } of String => JSON::Any, input_schema: input_schema, output_schema: output_schema) do |ctx|
          WorkflowNodeResult.continue(run_rag_node(ctx, config))
        end)
      end

      def suspend(
        id : String,
        reason : String = "human input required",
        resume_schema : Cogni::Workflows::DSL::Validator? = nil,
        input_schema : Cogni::Workflows::DSL::Validator? = nil,
        output_schema : Cogni::Workflows::DSL::Validator? = nil
      ) : self
        append_node(WorkflowNode.new(id, NodeKind::Suspend, metadata: {
          "reason" => JSON.parse(reason.to_json),
        } of String => JSON::Any, input_schema: input_schema, output_schema: output_schema) do |ctx|
          resume = ctx.resume_data || {} of String => JSON::Any

          if resume.empty?
            next WorkflowNodeResult.suspend(
              {
                "type" => JSON.parse("suspend".to_json),
                "node_id" => JSON.parse(id.to_json),
                "reason" => JSON.parse(reason.to_json),
              },
              id,
            )
          end

          if schema = resume_schema
            schema.validate(JSON.parse(resume.to_json), "$.resume")
          end

          WorkflowNodeResult.continue({
            "resume_data" => JSON.parse(resume.to_json),
          })
        end)
      end

      def parallel(parallel_nodes : Array(WorkflowNode)) : self
        ensure_not_committed!

        aggregator = WorkflowNode.new("parallel-#{@nodes.size}", NodeKind::Control) do |ctx|
          branch_results = Array(Tuple(Int32, WorkflowNodeResult)).new
          ch = Channel(Tuple(Int32, WorkflowNodeResult)).new

          parallel_nodes.each_with_index do |node, idx|
            spawn do
              begin
                ch.send({idx, node.execute(with_context_for(ctx, node))})
              rescue ex
                ch.send({idx, WorkflowNodeResult.fail(ex.message || "parallel node failed")})
              end
            end
          end

          parallel_nodes.size.times { branch_results << ch.receive }
          branch_results.sort_by! { |(idx, _)| idx }

          merged = {} of String => JSON::Any
          suspend_labels = [] of String
          suspend_payloads = [] of JSON::Any
          failed_result = nil.as(WorkflowNodeResult?)

          branch_results.each do |(_, result)|
            case result.action
            when NodeAction::Continue.to_s.downcase
              if data = result.data
                data.each { |k, v| merged[k] = v }
              end
            when NodeAction::Suspend.to_s.downcase
              labels = result.resume_labels || [] of String
              labels.each { |label| suspend_labels << label unless suspend_labels.includes?(label) }
              suspend_payloads << JSON.parse((result.suspend_payload || {} of String => JSON::Any).to_json)
            else
              failed_result = result
              break
            end
          end

          if failed = failed_result
            next failed
          end

          if suspend_labels.empty?
            WorkflowNodeResult.continue(merged)
          else
            WorkflowNodeResult.suspend(
              {
                "type" => JSON.parse("parallel_suspend".to_json),
                "resume_labels" => JSON.parse(suspend_labels.to_json),
                "branches" => JSON.parse(suspend_payloads.to_json),
              },
              resume_labels: suspend_labels,
            )
          end
        end

        @nodes << aggregator
        self
      end

      def foreach(node : WorkflowNode) : self
        append_node(node)
      end

      def while_do(condition : String, nodes : Array(WorkflowNode), max_iterations : Int32 = 100) : self
        ensure_not_committed!
        body = wrap_nodes_in_control(nodes, "while-body")
        append_node(WorkflowNode.new("while-#{@nodes.size}", NodeKind::Control) do |ctx|
          iterations = 0
          merged = {} of String => JSON::Any
          result = WorkflowNodeResult.continue

          while evaluate_condition(condition, with_state(ctx, merged)) && iterations < max_iterations
            iterations += 1
            result = body.execute(with_state(ctx, merged))
            break if result.action != NodeAction::Continue.to_s.downcase
            if data = result.data
              data.each { |k, v| merged[k] = v }
            end
          end

          result.action == NodeAction::Continue.to_s.downcase ? WorkflowNodeResult.continue(merged) : result
        end)
      end

      def until_do(condition : String, nodes : Array(WorkflowNode), max_iterations : Int32 = 100) : self
        ensure_not_committed!
        body = wrap_nodes_in_control(nodes, "until-body")
        append_node(WorkflowNode.new("until-#{@nodes.size}", NodeKind::Control) do |ctx|
          iterations = 0
          merged = {} of String => JSON::Any
          result = WorkflowNodeResult.continue

          while !evaluate_condition(condition, with_state(ctx, merged)) && iterations < max_iterations
            iterations += 1
            result = body.execute(with_state(ctx, merged))
            break if result.action != NodeAction::Continue.to_s.downcase
            if data = result.data
              data.each { |k, v| merged[k] = v }
            end
          end

          result.action == NodeAction::Continue.to_s.downcase ? WorkflowNodeResult.continue(merged) : result
        end)
      end

      def loop_do(nodes : Array(WorkflowNode), max_iterations : Int32 = 100) : self
        ensure_not_committed!
        body = wrap_nodes_in_control(nodes, "loop-body")
        append_node(WorkflowNode.new("loop-#{@nodes.size}", NodeKind::Control) do |ctx|
          iterations = 0
          merged = {} of String => JSON::Any
          result = WorkflowNodeResult.continue

          while iterations < max_iterations
            iterations += 1
            result = body.execute(with_state(ctx, merged))
            break if result.action != NodeAction::Continue.to_s.downcase
            if data = result.data
              data.each { |k, v| merged[k] = v }
            end
          end

          result.action == NodeAction::Continue.to_s.downcase ? WorkflowNodeResult.continue(merged) : result
        end)
      end

      def wait_for_event(event_name : String, resume_label : String? = nil) : self
        ensure_not_committed!

        waiter = WorkflowNode.new("wait-for-event-#{event_name}-#{@nodes.size}", NodeKind::Control) do |ctx|
          event = ctx.resume_data.try(&.["event_name"]?) || ctx.state["event_name"]?
          if event && event.raw == event_name
            WorkflowNodeResult.continue({"event_name" => JSON.parse(event_name.to_json)})
          else
            WorkflowNodeResult.suspend(
              {"reason" => JSON.parse("waiting for event #{event_name}".to_json)},
              resume_label || "event:#{event_name}",
            )
          end
        end

        @nodes << waiter
        self
      end

      def send_event(event_name : String, payload : AnyHash = {} of String => JSON::Any) : self
        ensure_not_committed!

        sender = WorkflowNode.new("send-event-#{event_name}-#{@nodes.size}", NodeKind::Control) do |_ctx|
          event_payload = {"event_name" => JSON.parse(event_name.to_json)}
          payload.each { |k, v| event_payload[k] = v }
          WorkflowNodeResult.continue(event_payload)
        end

        @nodes << sender
        self
      end

      def sleep(milliseconds : Int32) : self
        ensure_not_committed!
        sleeper = WorkflowNode.new("sleep-#{@nodes.size}", NodeKind::Control) do |_ctx|
          ::sleep(milliseconds / 1000.0)
          WorkflowNodeResult.continue
        end
        @nodes << sleeper
        self
      end

      def sleep_until(unix_time_seconds : Int64) : self
        ensure_not_committed!
        sleeper = WorkflowNode.new("sleep-until-#{@nodes.size}", NodeKind::Control) do |_ctx|
          now = Time.utc.to_unix
          remaining = unix_time_seconds - now
          ::sleep(remaining) if remaining > 0
          WorkflowNodeResult.continue
        end
        @nodes << sleeper
        self
      end

      def commit : self
        @committed = true
        self
      end

      def create_run(options : WorkflowRunOptions = WorkflowRunOptions.new) : WorkflowRunHandle
        run_id = options.run_id || "run_#{Time.utc.to_unix_ms}_#{Random.rand(100000)}"
        WorkflowRunHandle.new(self, run_id, options.resource_id)
      end

      def create_run_async(options : WorkflowRunOptions = WorkflowRunOptions.new) : WorkflowRunHandle
        create_run(options)
      end

      private def append_node(node : WorkflowNode) : self
        ensure_not_committed!
        @nodes << node
        self
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

    def self.create_workflow(id : String, description : String? = nil)
      WorkflowDefinition.new(id, description)
    end
  end
  end
end
