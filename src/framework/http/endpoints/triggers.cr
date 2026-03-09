module ACD
  module Kemal
    class App
      private def mount_trigger_endpoints
        post "/v1/triggers/workflows/:id" do |env|
          workflow_id = env.params.url["id"]
          body = json_body(env)
          start_workflow_run_from_body(env, workflow_id, body)
        end

        post "/v1/triggers/agents/:id" do |env|
          agent_id = env.params.url["id"]
          agent = agent_by_id(agent_id)

          unless agent
            next json_error(env, 404, "not_found", "agent not found: #{agent_id}")
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
              "id"          => "trg_agent_#{Random::Secure.hex(12)}",
              "object"      => "trigger.agent.response",
              "agent_id"    => agent[:id],
              "workflow_id" => agent[:workflow_id],
              "provider"    => response.provider,
              "model"       => response.model,
              "output_text" => response.text,
              "metadata"    => metadata,
            }.to_json
          rescue ex
            json_error(env, 422, "generation_error", ex.message || "agent generation failed")
          end
        end

        post "/v1/triggers/skills/:id" do |env|
          skill_id = env.params.url["id"]
          skill = skill_by_id(skill_id)

          unless skill
            next json_error(env, 404, "not_found", "skill not found: #{skill_id}")
          end

          body = json_body(env)
          env.response.content_type = "application/json"
          {
            "id"          => "trg_skill_#{Random::Secure.hex(12)}",
            "object"      => "trigger.skill.response",
            "skill_id"    => skill[:id],
            "workflow_id" => skill[:workflow_id],
            "status"      => "ok",
            "output"      => {
              "message" => "Skill execution scaffolded in CogniCore",
              "input"   => body,
            },
          }.to_json
        end

        post "/v1/triggers/functions/:id" do |env|
          fn_id = env.params.url["id"]
          body = json_body(env)
          input_data = body["input"]?.try(&.as_h?) || body["input_data"]?.try(&.as_h?) || body.dup
          ctx = Cogni::Workflow::NodeContext.new(
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
              "id"          => "trg_fn_#{Random::Secure.hex(12)}",
              "object"      => "trigger.function.response",
              "function_id" => fn_id,
              "output"      => result,
            }.to_json
          rescue ex
            json_error(env, 422, "function_error", ex.message || "function trigger failed")
          end
        end
      end
    end
  end
end
