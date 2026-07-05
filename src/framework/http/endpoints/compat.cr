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
          api_key = body["api_key"]?.try(&.as_s?)
          base_url = body["base_url"]?.try(&.as_s?)
          tools = body["tools"]?.try(&.as_a?)
          raw_messages = body["messages"]?.try(&.as_a?)

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
                              workflow_chat_output(snap)
                            else
                              run_result.to_json
                            end

              now = Time.utc.to_unix
              completion = {
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
              }
              next write_chat_completion_response(env, completion, stream_requested?(body))
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
              messages: raw_messages,
              tools: tools,
              metadata: metadata,
              api_key: api_key,
              base_url: base_url,
            )
          rescue ex
            env.response.status_code = 422
            env.response.content_type = "application/json"
            next({error: {type: "generation_error", message: ex.message || "chat completion failed"}}.to_json)
          end

          now = Time.utc.to_unix
          message = {"role" => "assistant", "content" => response.text}.to_h
          finish_reason = "stop"

          if tc = response.tool_calls
            message["tool_calls"] = tc
            finish_reason = "tool_calls"
          end

          completion = {
            "id" => "chatcmpl_#{Random::Secure.hex(12)}",
            "object" => "chat.completion",
            "created" => now,
            "model" => response.model,
            "choices" => [
              {
                "index" => 0,
                "message" => message,
                "finish_reason" => finish_reason,
              },
            ],
            "usage" => {
              "prompt_tokens" => 0,
              "completion_tokens" => 0,
              "total_tokens" => 0,
            },
          }
          write_chat_completion_response(env, completion, stream_requested?(body))
        end
      end

      private def stream_requested?(body : Hash(String, JSON::Any)) : Bool
        body["stream"]?.try(&.as_bool?) || false
      end

      private def write_chat_completion_response(env, completion, stream : Bool) : String
        unless stream
          env.response.status_code = 200
          env.response.content_type = "application/json"
          return completion.to_json
        end

        env.response.status_code = 200
        env.response.content_type = "text/event-stream"
        env.response.headers["Cache-Control"] = "no-cache"
        env.response.headers["Connection"] = "keep-alive"

        parsed_completion = JSON.parse(completion.to_json)
        completion_hash = parsed_completion.as_h
        id = completion_hash["id"]
        created = completion_hash["created"]
        model = completion_hash["model"]
        choices = completion_hash["choices"].as_a
        message = choices[0]["message"].as_h
        content = message["content"]?.try(&.as_s?) || ""
        finish_reason_val = choices[0]["finish_reason"]?.try(&.as_s?)

        # First chunk: role
        role_chunk = {
          "id" => id,
          "object" => "chat.completion.chunk",
          "created" => created,
          "model" => model,
          "choices" => [
            {
              "index" => 0,
              "delta" => {
                "role" => "assistant",
              },
              "finish_reason" => nil,
            },
          ],
        }
        env.response.print "data: #{role_chunk.to_json}\n\n"

        # Content chunks
        if content && !content.empty?
          content_chunk = {
            "id" => id,
            "object" => "chat.completion.chunk",
            "created" => created,
            "model" => model,
            "choices" => [
              {
                "index" => 0,
                "delta" => {
                  "content" => content,
                },
                "finish_reason" => nil,
              },
            ],
          }
          env.response.print "data: #{content_chunk.to_json}\n\n"
        end

        # Tool call chunks
        if tool_calls = message["tool_calls"]?.try(&.as_a?)
          tool_calls.each do |tc|
            tc_hash = tc.as_h
            tc_id = tc_hash["id"]?.try(&.as_s?) || "call_#{Random::Secure.hex(8)}"
            tc_type = tc_hash["type"]?.try(&.as_s?) || "function"
            tc_function = tc_hash["function"]?.try(&.as_h?)
            tc_name = tc_function.try(&.["name"]?.try(&.as_s?)) || ""
            tc_args = tc_function.try(&.["arguments"]?.try(&.as_s?)) || "{}"

            tool_chunk = {
              "id" => id,
              "object" => "chat.completion.chunk",
              "created" => created,
              "model" => model,
              "choices" => [
                {
                  "index" => 0,
                  "delta" => {
                    "tool_calls" => [
                      {
                        "index" => 0,
                        "id" => tc_id,
                        "type" => tc_type,
                        "function" => {
                          "name" => tc_name,
                          "arguments" => tc_args,
                        },
                      },
                    ],
                  },
                  "finish_reason" => nil,
                },
              ],
            }
            env.response.print "data: #{tool_chunk.to_json}\n\n"
          end
        end

        # Final chunk
        final_delta = {"content" => nil}.to_h
        if finish_reason_val
          final_chunk = {
            "id" => id,
            "object" => "chat.completion.chunk",
            "created" => created,
            "model" => model,
            "choices" => [
              {
                "index" => 0,
                "delta" => {} of String => JSON::Any,
                "finish_reason" => finish_reason_val,
              },
            ],
          }
          env.response.print "data: #{final_chunk.to_json}\n\n"
        end

        env.response.print "data: [DONE]\n\n"
        ""
      end

      private def workflow_chat_output(snapshot : Ocawe::Workflow::WorkflowRunSnapshot) : String
        if state = snapshot.state
          if text = state["text"]?.try(&.as_s?)
            return text
          end
          if content = state["content"]?.try(&.as_s?)
            return content
          end
        end

        if output = snapshot.output
          if text = output["text"]?.try(&.as_s?)
            return text
          end
          if content = output["content"]?.try(&.as_s?)
            return content
          end
          return output.to_json
        end

        snapshot.to_json
      end
    end
  end
end
