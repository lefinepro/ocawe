module ACD
  module HTTP
    class App
      private def mount_trigger_endpoints
        post "/v1/triggers/workflows/:id" do |env|
          workflow_id = env.params.url["id"]
          body = json_body(env)
          input_data = body["input_data"]?.try(&.as_h?) || body["input"]?.try(&.as_h?) || body.dup
          resources = body["resources"]?.try(&.as_h?)
          input_data.delete("resources")
          run_id = body["run_id"]?.try(&.as_s?)
          resource_id = body["resource_id"]?.try(&.as_s?)

          result_or_error = with_workflow_errors(env) do
            @workflow_service.start_run(workflow_id, run_id: run_id, resource_id: resource_id, input_data: input_data, resources: resources)
          end
          if result_or_error.is_a?(String)
            next result_or_error
          end
          run_result = result_or_error.as(Cogni::Workflows::Declarative::WorkflowRunResult)
          env.response.status_code = 201
          env.response.content_type = "application/json"
          @workflow_service.load_snapshot(workflow_id, run_result.run_id).try(&.to_json) || run_result.to_json
        end

        post "/v1/triggers/agents/:id" do |env|
          agent_id = env.params.url["id"]
          agent = agent_by_id(agent_id)

          unless agent
            env.response.status_code = 404
            env.response.content_type = "application/json"
            next({error: {type: "not_found", message: "agent not found: #{agent_id}"}}.to_json)
          end

          body = json_body(env)
          model = body["model"]?.try(&.as_s?) || agent[:model] || agent[:default_model] || FALLBACK_CHAT_MODEL
          messages = extract_chat_messages(body)
          prompt = chat_prompt_from_messages(messages, body)
          system_message = chat_system_message(messages, body)
          metadata = body["metadata"]?.try(&.as_h?) || {} of String => JSON::Any
          metadata["agent_id"] = JSON.parse(agent_id.to_json)
          metadata["workflow_id"] = JSON.parse(agent[:workflow_id].to_json)

          begin
            response = CogniCore::AI::Client.new.generate_text(
              model_spec: model,
              prompt: prompt,
              system: [agent[:prompt], system_message].compact.reject(&.empty?).join("\n\n"),
              metadata: metadata,
            )
            env.response.content_type = "application/json"
            {
              "id" => "trg_agent_#{Random::Secure.hex(12)}",
              "object" => "trigger.agent.response",
              "agent_id" => agent[:id],
              "workflow_id" => agent[:workflow_id],
              "provider" => response.provider,
              "model" => response.model,
              "output_text" => response.text,
              "metadata" => metadata,
            }.to_json
          rescue ex
            env.response.status_code = 422
            env.response.content_type = "application/json"
            {error: {type: "generation_error", message: ex.message || "agent generation failed"}}.to_json
          end
        end

        post "/v1/triggers/skills/:id" do |env|
          skill_id = env.params.url["id"]
          skill = skill_by_id(skill_id)

          unless skill
            env.response.status_code = 404
            env.response.content_type = "application/json"
            next({error: {type: "not_found", message: "skill not found: #{skill_id}"}}.to_json)
          end

          body = json_body(env)
          env.response.content_type = "application/json"
          {
            "id" => "trg_skill_#{Random::Secure.hex(12)}",
            "object" => "trigger.skill.response",
            "skill_id" => skill[:id],
            "workflow_id" => skill[:workflow_id],
            "status" => "ok",
            "output" => {
              "message" => "Skill execution scaffolded in CogniCore",
              "input" => body,
            },
          }.to_json
        end

        post "/v1/triggers/functions/:id" do |env|
          fn_id = env.params.url["id"]
          body = json_body(env)
          input_data = body["input"]?.try(&.as_h?) || body["input_data"]?.try(&.as_h?) || body.dup
          ctx = Cogni::Workflows::Declarative::NodeContext.new(
            workflow_id: body["workflow_id"]?.try(&.as_s?) || "trigger:function",
            run_id: body["run_id"]?.try(&.as_s?) || "trigger_#{Random::Secure.hex(8)}",
            node_id: fn_id,
            input_data: input_data,
            state: body["state"]?.try(&.as_h?) || {} of String => JSON::Any,
          )

          begin
            result = Cogni::RegistryApi.call_function(fn_id, ctx)
            env.response.content_type = "application/json"
            {
              "id" => "trg_fn_#{Random::Secure.hex(12)}",
              "object" => "trigger.function.response",
              "function_id" => fn_id,
              "output" => result,
            }.to_json
          rescue ex
            env.response.status_code = 422
            env.response.content_type = "application/json"
            {error: {type: "function_error", message: ex.message || "function trigger failed"}}.to_json
          end
        end
      end
    end
  end
end
