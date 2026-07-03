module ACD
  module Kemal
    class App
      CHAT_COMPLETION_TASKS_DATASET = "chat_completion_tasks"

      private def mount_compat_endpoints
        post "/v1/responses" { |env| not_implemented(env, "responses endpoint pending Kemal integration") }
        post "/v1/chat/completions" do |env|
          body = json_body(env)
          begin
            completion = build_chat_completion(body)
            write_chat_completion_response(env, completion, stream_requested?(body))
          rescue ex
            env.response.status_code = completion_error_status(ex)
            env.response.content_type = "application/json"
            {error: {type: "completion_error", message: ex.message || "chat completion failed"}}.to_json
          end
        end

        post "/v1/chat/completions/tasks" do |env|
          body = json_body(env)
          task_id = body["task_id"]?.try(&.as_s?) || "chatcmpltask_#{Random::Secure.hex(12)}"
          ensure_chat_completion_tasks_dataset
          queued_payload = chat_completion_task_payload(
            task_id: task_id,
            status: "queued",
            request: body,
          )
          @dataset_service.add_items(CHAT_COMPLETION_TASKS_DATASET, [queued_payload])

          spawn do
            run_chat_completion_task(task_id, body)
          end

          env.response.status_code = 202
          env.response.content_type = "application/json"
          {
            "task_id" => task_id,
            "status" => "queued",
            "status_url" => "/v1/chat/completions/tasks/#{task_id}",
          }.to_json
        rescue ex
          env.response.status_code = 422
          env.response.content_type = "application/json"
          {error: {type: "task_enqueue_error", message: ex.message || "failed to enqueue completion task"}}.to_json
        end

        get "/v1/chat/completions/tasks/:taskId" do |env|
          task_id = env.params.url["taskId"]
          task = find_chat_completion_task(task_id)
          unless task
            env.response.status_code = 404
            env.response.content_type = "application/json"
            next({error: {type: "not_found", message: "completion task not found: #{task_id}"}}.to_json)
          end

          env.response.content_type = "application/json"
          task.payload.to_json
        end
      end

      private def build_chat_completion(body : Ocawe::Workflow::AnyHash) : Ocawe::Workflow::AnyHash
        model = body["model"]?.try(&.as_s?) || FALLBACK_CHAT_MODEL
        messages = extract_chat_messages(body)
        prompt = chat_prompt_from_messages(messages, body)
        system_message = chat_system_message(messages, body)
        metadata = body["metadata"]?.try(&.as_h?) || {} of String => JSON::Any
        api_key = body["api_key"]?.try(&.as_s?)
        base_url = body["base_url"]?.try(&.as_s?)

        # Check if model is a workflow reference (e.g. "workflow/orator")
        if model.starts_with?("workflow/")
          workflow_id = model.sub("workflow/", "")
          workflow = workflow_by_id(workflow_id)

          unless workflow
            raise "workflow not found: #{workflow_id}"
          end

          # Execute workflow with chat input
          input_data = {
            "prompt" => JSON.parse(prompt.to_json),
            "messages" => JSON.parse(messages.to_json),
          } of String => JSON::Any
          input_data["system"] = JSON.parse(system_message.to_json) if system_message

          run_result = @workflow_service.start_run(workflow_id, input_data: input_data)
          snapshot = @workflow_service.load_snapshot(workflow_id, run_result.run_id)
          output_text = if snap = snapshot
                          workflow_chat_output(snap)
                        else
                          run_result.to_json
                        end
          now = Time.utc.to_unix

          return JSON.parse({
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
          }.to_json).as_h
        end

        # Standard AI model execution
        response = OcaweCore::AI::Client.new.generate_text(
          model_spec: model,
          prompt: prompt,
          system: system_message,
          metadata: metadata,
          api_key: api_key,
          base_url: base_url,
        )

        now = Time.utc.to_unix
        JSON.parse({
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
        }.to_json).as_h
      end

      private def completion_error_status(ex : Exception) : Int32
        message = ex.message || ""
        return 404 if message.includes?("not found") || message.includes?("unknown workflow")
        422
      end

      private def ensure_chat_completion_tasks_dataset : Nil
        return if @dataset_service.get_dataset(CHAT_COMPLETION_TASKS_DATASET)

        @dataset_service.create_dataset(
          CHAT_COMPLETION_TASKS_DATASET,
          description: "OpenAI-compatible chat completion task queue",
        )
      rescue ex
        raise ex unless (ex.message || "").includes?("already exists")
      end

      private def find_chat_completion_task(task_id : String) : Ocawe::Dataset::ItemRecord?
        ensure_chat_completion_tasks_dataset
        @dataset_service.list_items(CHAT_COMPLETION_TASKS_DATASET).find { |item| item.id == task_id }
      end

      private def run_chat_completion_task(task_id : String, request : Ocawe::Workflow::AnyHash) : Nil
        update_chat_completion_task(
          task_id,
          chat_completion_task_payload(
            task_id: task_id,
            status: "running",
            request: request,
          ),
        )

        result = build_chat_completion(request)
        update_chat_completion_task(
          task_id,
          chat_completion_task_payload(
            task_id: task_id,
            status: "completed",
            request: request,
            result: result,
          ),
        )
      rescue ex
        update_chat_completion_task(
          task_id,
          chat_completion_task_payload(
            task_id: task_id,
            status: "failed",
            request: request,
            error: ex.message || "completion task failed",
          ),
        )
      end

      private def update_chat_completion_task(task_id : String, payload : Ocawe::Workflow::AnyHash) : Nil
        ensure_chat_completion_tasks_dataset
        @dataset_service.update_item(CHAT_COMPLETION_TASKS_DATASET, task_id, payload)
      end

      private def chat_completion_task_payload(
        task_id : String,
        status : String,
        request : Ocawe::Workflow::AnyHash,
        result : Ocawe::Workflow::AnyHash? = nil,
        error : String? = nil
      ) : Ocawe::Workflow::AnyHash
        now = Time.utc.to_s
        JSON.parse({
          "id" => task_id,
          "task_id" => task_id,
          "status" => status,
          "request" => request,
          "result" => result,
          "error" => error,
          "updated_at" => now,
        }.to_json).as_h
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
        content = completion_hash["choices"].as_a[0]["message"]["content"].as_s

        chunk = {
          "id" => id,
          "object" => "chat.completion.chunk",
          "created" => created,
          "model" => model,
          "choices" => [
            {
              "index" => 0,
              "delta" => {
                "role" => "assistant",
                "content" => content,
              },
              "finish_reason" => nil,
            },
          ],
        }
        final_chunk = {
          "id" => id,
          "object" => "chat.completion.chunk",
          "created" => created,
          "model" => model,
          "choices" => [
            {
              "index" => 0,
              "delta" => {} of String => String,
              "finish_reason" => "stop",
            },
          ],
        }

        env.response.print "data: #{chunk.to_json}\n\n"
        env.response.print "data: #{final_chunk.to_json}\n\n"
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
