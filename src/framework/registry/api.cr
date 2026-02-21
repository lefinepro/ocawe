require "../workflows/declarative/run"
require "../cognicore/ai/client"

module Cogni
  module RegistryApi
    extend self

    alias AnyHash = Cogni::Workflow::AnyHash
    alias Validator = Cogni::Workflows::DSL::Validator
    alias WorkflowDefinition = Cogni::Workflow::WorkflowDefinition
    alias WorkflowNode = Cogni::Workflow::WorkflowNode
    alias WorkflowNodeResult = Cogni::Workflow::WorkflowNodeResult
    alias NodeContext = Cogni::Workflow::NodeContext
    alias NodeKind = Cogni::Workflow::NodeKind

    def reset_all! : Nil
      Cogni::Workflow.reset_node_kind_registry!
      Cogni::Workflow.reset_resource_registry!
      Cogni::Workflow.reset_function_registry!
    end

    def register_system_function(
      name : String,
      alias_name : String? = nil,
      &block : NodeContext -> Cogni::Workflow::RunnableResult
    ) : String
      Cogni::Workflow.register_system_function(name, alias_name: alias_name, &block)
    end

    def register_function(
      name : String,
      alias_name : String? = nil,
      source : Cogni::Workflow::FunctionSource = Cogni::Workflow::FunctionSource::User,
      &block : NodeContext -> Cogni::Workflow::RunnableResult
    ) : String
      Cogni::Workflow.register_function(name, alias_name: alias_name, source: source, &block)
    end

    def call_function(name : String, ctx : NodeContext) : AnyHash
      Cogni::Workflow.function_registry.call(name, ctx)
    end

    def node_kind(
      kind : String,
      &block : NodeContext, AnyHash -> Cogni::Workflow::NodeKindResult
    ) : Nil
      Cogni::Workflow.register_node_kind(kind, &block)
    end

    def resource(
      name : String,
      &block : NodeContext, AnyHash -> AnyHash
    ) : Nil
      Cogni::Workflow.register_resource(name, &block)
    end

    def build_node(
      workflow : WorkflowDefinition,
      type : String,
      id : String,
      runtime : AnyHash? = nil,
      env : AnyHash? = nil,
      workflow_root : String? = nil,
      params : AnyHash? = nil,
      prompt : String? = nil,
      model : String? = nil,
      resume_schema : Validator? = nil,
      voice_config : AnyHash? = nil,
      guardrails_config : AnyHash? = nil,
      agent_id : String? = nil,
      agent : String? = nil,
      config : AnyHash? = nil,
      reason : String? = nil,
      node_kind_name : String? = nil,
      node_kind_parameters : AnyHash? = nil,
      input_schema : Validator? = nil,
      output_schema : Validator? = nil
    ) : WorkflowNode
      normalized = type.strip.downcase

      case normalized
      when "run"
        metadata = {} of String => JSON::Any
        metadata["runtime"] = JSON.parse(runtime.to_json) if runtime
        metadata["env"] = JSON.parse(env.to_json) if env
        metadata["workflow_root"] = JSON.parse(workflow_root.to_json) if workflow_root
        metadata["params"] = JSON.parse(params.to_json) if params

        executor = Cogni::Workflow::RunExecutor.new
        return WorkflowNode.new(id, NodeKind::Run, metadata: metadata, input_schema: input_schema, output_schema: output_schema) do |ctx|
          WorkflowNodeResult.continue(executor.run(id, ctx, runtime: runtime, env: env, workflow_root: workflow_root))
        end
      when "agent"
        metadata = {} of String => JSON::Any
        metadata["has_resume_schema"] = JSON.parse(true.to_json) if resume_schema

        return WorkflowNode.new(id, NodeKind::Agent, metadata: metadata, input_schema: input_schema, output_schema: output_schema) do |ctx|
          user_prompt = build_agent_user_prompt(ctx)
          Cogni::Workflow::Guardrails.validate_input!(id, user_prompt, guardrails_config)

          resolved_model = resolve_model(workflow, ctx, model)
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
          agent_result = Cogni::Workflow::AgentResult.new(
            agent_type: "default-agent",
            content: response.text,
            provider: response.provider,
            model: "#{response.provider}/#{response.model}",
          )

          Cogni::Workflow::Guardrails.validate_output!(id, agent_result.content, guardrails_config)

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
        end
      when "skill"
        meta = {} of String => JSON::Any
        selected_agent = agent || agent_id
        meta["agent_id"] = JSON.parse(selected_agent.to_json) if selected_agent
        return WorkflowNode.new(id, NodeKind::Skill, metadata: meta, input_schema: input_schema, output_schema: output_schema) { |_ctx| WorkflowNodeResult.continue }
      when "voice"
        resolved_config = config || ({} of String => JSON::Any)
        return WorkflowNode.new(id, NodeKind::Voice, metadata: {
          "dsl_kind" => JSON.parse("voice".to_json),
          "config" => JSON.parse(resolved_config.to_json),
        } of String => JSON::Any, input_schema: input_schema, output_schema: output_schema) do |ctx|
          WorkflowNodeResult.continue(run_voice_node(ctx, resolved_config))
        end
      when "rag"
        resolved_config = config || ({} of String => JSON::Any)
        return WorkflowNode.new(id, NodeKind::Rag, metadata: {
          "dsl_kind" => JSON.parse("rag".to_json),
          "config" => JSON.parse(resolved_config.to_json),
        } of String => JSON::Any, input_schema: input_schema, output_schema: output_schema) do |ctx|
          WorkflowNodeResult.continue(Cogni::Workflow::RagRuntime.execute(ctx, resolved_config))
        end
      when "suspend"
        suspend_reason = reason || "human input required"
        return WorkflowNode.new(id, NodeKind::Suspend, metadata: {
          "reason" => JSON.parse(suspend_reason.to_json),
        } of String => JSON::Any, input_schema: input_schema, output_schema: output_schema) do |ctx|
          resume = ctx.resume_data || {} of String => JSON::Any

          if resume.empty?
            next WorkflowNodeResult.suspend(
              {
                "type" => JSON.parse("suspend".to_json),
                "node_id" => JSON.parse(id.to_json),
                "reason" => JSON.parse(suspend_reason.to_json),
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
        end
      when "agent_cliproxy", "agent_codex", "agent_opencode"
        metadata = {} of String => JSON::Any
        metadata["params"] = JSON.parse(params.to_json) if params
        return WorkflowNode.new(id, NodeKind::Run, metadata: metadata, input_schema: input_schema, output_schema: output_schema) do |ctx|
          WorkflowNodeResult.continue(call_function(normalized, ctx))
        end
      when "node_kind"
        kind_name = node_kind_name || id
        kind_params = node_kind_parameters || ({} of String => JSON::Any)
        metadata = {
          "node_kind" => JSON.parse(kind_name.to_json),
          "parameters" => JSON.parse(kind_params.to_json),
        } of String => JSON::Any

        return WorkflowNode.new(id, NodeKind::Custom, metadata: metadata, input_schema: input_schema, output_schema: output_schema) do |ctx|
          raw = Cogni::Workflow.node_kind_registry.call(kind_name, ctx, kind_params)
          case raw
          when WorkflowNodeResult
            raw
          when Hash(String, JSON::Any)
            WorkflowNodeResult.continue(raw)
          else
            raise "unsupported node kind result for #{kind_name}"
          end
        end
      else
        raise "unknown registry node type: #{type}"
      end
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

    private def resolve_model(workflow : WorkflowDefinition, ctx : NodeContext, agent_model : String?) : String
      request_model = ctx.input_data["model"]?.try(&.as_s?) || ctx.state["model"]?.try(&.as_s?)
      return request_model if request_model
      return agent_model if agent_model
      ctx.state["workflow_model"]?.try(&.as_s?) || workflow.default_model || "openai/gpt-4.1-mini"
    end
  end

  module Registry
    extend self

    def node_kind(
      kind : String,
      &block : Cogni::Workflow::NodeContext, Cogni::Workflow::AnyHash -> Cogni::Workflow::NodeKindResult
    ) : Nil
      Cogni::RegistryApi.node_kind(kind, &block)
    end

    def resource(
      name : String,
      &block : Cogni::Workflow::NodeContext, Cogni::Workflow::AnyHash -> Cogni::Workflow::AnyHash
    ) : Nil
      Cogni::RegistryApi.resource(name, &block)
    end
  end
end
