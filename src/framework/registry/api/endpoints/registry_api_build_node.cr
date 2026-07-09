module Ocawe
  module RegistryApi
    extend self

    def build_node(
      workflow : WorkflowDefinition,
      type : String,
      id : String,
      runtime : AnyHash? = nil,
      env : AnyHash? = nil,
      workflow_root : String? = nil,
      attributes : AnyHash? = nil,
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
      node_kind_attributes : AnyHash? = nil,
      workspace : AnyHash? = nil,
      input_schema : Validator? = nil,
      output_schema : Validator? = nil
    ) : WorkflowNode
      normalized = type.strip.downcase

      case normalized
      when "exec"
        if runtime.nil? && !id.starts_with?("mcp:")
          raise "exec requires runtime; internal Crystal functions must be node kinds"
        end

        metadata = {} of String => JSON::Any
        metadata["runtime"] = JSON.parse(runtime.to_json) if runtime
        metadata["env"] = JSON.parse(env.to_json) if env
        metadata["workflow_root"] = JSON.parse(workflow_root.to_json) if workflow_root
        metadata["attributes"] = JSON.parse(attributes.to_json) if attributes
        metadata["workspace"] = JSON.parse(workspace.to_json) if workspace

        executor = Ocawe::Workflow::ExecExecutor.new
        return WorkflowNode.new(id, NodeKind::Exec, metadata: metadata, input_schema: input_schema, output_schema: output_schema) do |ctx|
          WorkflowNodeResult.continue(executor.exec(id, ctx, runtime: runtime, env: env, workflow_root: workflow_root))
        end
      when "agent"
        metadata = {} of String => JSON::Any
        metadata["has_resume_schema"] = JSON.parse(true.to_json) if resume_schema
        metadata["workspace"] = JSON.parse(workspace.to_json) if workspace

        return WorkflowNode.new(id, NodeKind::Agent, metadata: metadata, input_schema: input_schema, output_schema: output_schema) do |ctx|
          user_prompt = build_agent_user_prompt(ctx)
          Ocawe::Workflow::Guardrails.validate_input!(id, user_prompt, guardrails_config)

          resolved_model = resolve_model(workflow, ctx, model)
          system_prompt = prompt || "You are agent #{id}."
          metadata = {
            "workflow_id" => JSON.parse(ctx.workflow_id.to_json),
            "run_id"      => JSON.parse(ctx.run_id.to_json),
            "node_id"     => JSON.parse(ctx.node_id.to_json),
            "agent_id"    => JSON.parse(id.to_json),
          } of String => JSON::Any

          response = OcaweCore::AI::Client.new.generate_text(
            model_spec: resolved_model,
            prompt: user_prompt,
            system: system_prompt,
            metadata: metadata,
          )
          agent_payload = Ocawe::Workflow::AgentResult.new(
            agent_type: "default-agent",
            content: response.text,
            provider: response.provider,
            model: resolved_model,
          ).to_any_hash

          agent_content = agent_payload["content"]?.try(&.as_s?) || ""

          Ocawe::Workflow::Guardrails.validate_output!(id, agent_content, guardrails_config)

          outputs = ctx.state["agent_outputs"]?.try(&.as_h?) || {} of String => JSON::Any
          outputs = outputs.dup
          outputs[id] = JSON.parse(agent_payload.to_json)

          result = {
            "agent_outputs" => JSON.parse(outputs.to_json),
            "agent_result"  => JSON.parse(agent_payload.to_json),
            "last_agent"    => JSON.parse(id.to_json),
            "last_model"    => JSON.parse((agent_payload["model"]?.try(&.as_s?) || resolved_model).to_json),
            "last_response" => JSON.parse(agent_content.to_json),
            "active_agent"  => JSON.parse(id.to_json),
          } of String => JSON::Any

          if parsed_payload = parse_agent_json_payload(agent_content)
            parsed_payload.each do |k, v|
              result[k] = JSON.parse(v.to_json)
            end
          end

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
          "config"   => JSON.parse(resolved_config.to_json),
        } of String => JSON::Any, input_schema: input_schema, output_schema: output_schema) do |ctx|
          WorkflowNodeResult.continue(run_voice_node(ctx, resolved_config))
        end
      when "rag"
        resolved_config = config || ({} of String => JSON::Any)
        return WorkflowNode.new(id, NodeKind::Rag, metadata: {
          "dsl_kind" => JSON.parse("rag".to_json),
          "config"   => JSON.parse(resolved_config.to_json),
        } of String => JSON::Any, input_schema: input_schema, output_schema: output_schema) do |ctx|
          WorkflowNodeResult.continue(Ocawe::Workflow::RagRuntime.execute(ctx, resolved_config))
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
                "type"    => JSON.parse("suspend".to_json),
                "node_id" => JSON.parse(id.to_json),
                "reason"  => JSON.parse(suspend_reason.to_json),
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

      when "node_kind"
        kind_name = node_kind_name || id
        kind_attributes = node_kind_attributes || ({} of String => JSON::Any)
        metadata = {
          "node_kind"  => JSON.parse(kind_name.to_json),
          "attributes" => JSON.parse(kind_attributes.to_json),
        } of String => JSON::Any
        metadata["workspace"] = JSON.parse(workspace.to_json) if workspace

        return WorkflowNode.new(id, NodeKind::Custom, metadata: metadata, input_schema: input_schema, output_schema: output_schema) do |ctx|
          raw = Ocawe::Workflow.node_kind_registry.call(kind_name, ctx, kind_attributes)
          case raw
          when WorkflowNodeResult
            raw
          when Hash(String, JSON::Any)
            WorkflowNodeResult.continue(raw)
          else
            raise "unsupported node kind result for #{kind_name}"
          end
        end

      when "follow"
        resolved_config = config || ({} of String => JSON::Any)
        actors = resolved_config["actors"]?.try(&.as_a?) || [] of JSON::Any
        actor_strings = actors.compact_map { |a| a.as_s? }

        return WorkflowNode.new(id, NodeKind::Federation, metadata: {
          "dsl_kind" => JSON.parse("follow".to_json),
          "actors"   => JSON.parse(actor_strings.to_json),
        } of String => JSON::Any, input_schema: input_schema, output_schema: output_schema) do |ctx|
          # Generate workflow actor DID and send Follow activities
          workflow_id = ctx.workflow_id
          run_id = ctx.run_id

          # Get base_url from request_context or use default
          base_url = ctx.request_context.try { |rc| rc["base_url"]?.try(&.as_s?) } || "http://localhost:4111"

          # Create local workflow actor ID (DID-like format)
          local_actor_id = "workflow:#{workflow_id}:#{run_id}"
          local_actor_url = "#{base_url}/actors/#{local_actor_id}"

          # Store follow configuration for federation system
          follow_records = [] of Hash(String, JSON::Any)

          actor_strings.each do |remote_actor|
            follow_record = {
              "local_actor" => JSON.parse(local_actor_url.to_json),
              "local_actor_id" => JSON.parse(local_actor_id.to_json),
              "remote_actor" => JSON.parse(remote_actor.to_json),
              "status" => JSON.parse("pending".to_json),
              "created_at" => JSON.parse(Time.utc.to_rfc3339.to_json),
            } of String => JSON::Any

            follow_records << follow_record
          end

          result = {
            "follow_actors" => JSON.parse(actor_strings.to_json),
            "follow_records" => JSON.parse(follow_records.to_json),
            "follow_status" => JSON.parse("registered".to_json),
            "local_actor_id" => JSON.parse(local_actor_id.to_json),
            "local_actor_url" => JSON.parse(local_actor_url.to_json),
          } of String => JSON::Any

          WorkflowNodeResult.continue(result)
        end

      else
        raise "unknown registry node type: #{type}"
      end
    end
  end
end
