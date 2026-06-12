module ACD
  module Kemal
    class App
      private def mount_compat_endpoints
        post "/v1/responses" { |env| not_implemented(env, "responses endpoint pending Kemal integration") }
        post "/v1/chat/completions" do |env|
          body = json_body(env)
          model = body["model"]?.try(&.as_s?) || FALLBACK_CHAT_MODEL
          messages = extract_chat_messages(body)
          prompt = chat_prompt_from_messages(messages, body)
          system_message = chat_system_message(messages, body)
          metadata = body["metadata"]?.try(&.as_h?) || {} of String => JSON::Any

          # Check if model is a workflow reference (e.g. "workflow/orator")
          if model.starts_with?("workflow/")
            workflow_id = model.sub("workflow/", "")
            workflow = workflow_by_id(workflow_id)

            unless workflow
              env.response.status_code = 404
              env.response.content_type = "application/json"
              next({error: {type: "not_found", message: "workflow not found: #{workflow_id}"}}.to_json)
            end

            # Execute workflow with chat input
            input_data = {
              "prompt" => JSON.parse(prompt.to_json),
              "messages" => JSON.parse(messages.to_json),
            } of String => JSON::Any
            input_data["system"] = JSON.parse(system_message.to_json) if system_message

            begin
              result_or_error = with_workflow_errors(env) do
                @workflow_service.start_run(workflow_id, input_data: input_data)
              end

              if result_or_error.is_a?(String)
                env.response.status_code = 422
                env.response.content_type = "application/json"
                next(result_or_error)
              end

              run_result = result_or_error.as(Ocawe::Workflow::WorkflowRunResult)
              snapshot = @workflow_service.load_snapshot(workflow_id, run_result.run_id)

              # Extract text from workflow output
              output_text = if snap = snapshot
                              if text = snap["text"]?.try(&.as_s?)
                                text
                              elsif content = snap["content"]?.try(&.as_s?)
                                content
                              elsif output = snap["output"]?
                                output.to_json
                              else
                                snap.to_json
                              end
                            else
                              run_result.to_json
                            end

              now = Time.utc.to_unix
              env.response.status_code = 201
              env.response.content_type = "application/json"
              next({
                "id" => "chatcmpl_#{Random::Secure.hex(12)}",
                "object" => "chat.completion",
                "created" => now,
                "model" => model,
                "choices" => [
                  {
                    "index" => 0,
                    "message" => {
                      "role" => "assistant",
                      "content" => output_text,
                    },
                    "finish_reason" => "stop",
                  },
                ],
                "usage" => {
                  "prompt_tokens" => 0,
                  "completion_tokens" => 0,
                  "total_tokens" => 0,
                },
              }.to_json)
            rescue ex
              env.response.status_code = 422
              env.response.content_type = "application/json"
              next({error: {type: "workflow_error", message: ex.message || "workflow execution failed"}}.to_json)
            end
          end

          # Standard AI model execution
          begin
            response = OcaweCore::AI::Client.new.generate_text(
              model_spec: model,
              prompt: prompt,
              system: system_message,
              metadata: metadata,
            )
          rescue ex
            env.response.status_code = 422
            env.response.content_type = "application/json"
            next({error: {type: "generation_error", message: ex.message || "chat completion failed"}}.to_json)
          end

          now = Time.utc.to_unix
          env.response.content_type = "application/json"
          {
            "id" => "chatcmpl_#{Random::Secure.hex(12)}",
            "object" => "chat.completion",
            "created" => now,
            "model" => response.model,
            "choices" => [
              {
                "index" => 0,
                "message" => {
                  "role" => "assistant",
                  "content" => response.text,
                },
                "finish_reason" => "stop",
              },
            ],
            "usage" => {
              "prompt_tokens" => 0,
              "completion_tokens" => 0,
              "total_tokens" => 0,
            },
          }.to_json
        end
      end
    end
  end
end
