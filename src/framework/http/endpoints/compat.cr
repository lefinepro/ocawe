module ACD
  module Kemal
    class App
      CHAT_COMPLETION_TASKS_DATASET = "chat_completion_tasks"

      private def mount_compat_endpoints
        post "/v1/responses" { |env| not_implemented(env, "responses endpoint pending Kemal integration") }
        get "/v1/chat/completions/:completion_id" do |env|
          completion_id = env.params.url["completion_id"]
          if completion = retrieve_chat_completion(completion_id)
            env.response.status_code = 200
            env.response.content_type = "application/json"
            next completion.to_json
          end

          env.response.status_code = 404
          env.response.content_type = "application/json"
          {
            "error" => {
              "type" => "not_found",
              "message" => "chat completion not found: #{completion_id}",
            },
          }.to_json
        end

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
        tools = body["tools"]?.try(&.as_a?)
        raw_messages = body["messages"]?.try(&.as_a?)

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
            "id" => workflow_chat_completion_id(snapshot, workflow_id) || "chatcmpl_#{Random::Secure.hex(12)}",
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
          messages: raw_messages,
          tools: tools,
          metadata: metadata,
          api_key: api_key,
          base_url: base_url,
        )

        now = Time.utc.to_unix
        message = {"role" => JSON::Any.new("assistant"), "content" => JSON::Any.new(response.text)} of String => JSON::Any
        finish_reason = "stop"

        if tc = response.tool_calls
          message["tool_calls"] = JSON::Any.new(tc)
          finish_reason = "tool_calls"
        end

        JSON.parse({
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

      private def retrieve_chat_completion(completion_id : String)
        ref = chat_completion_task_ref(completion_id)
        return nil if ref.empty?

        task = load_chat_completion_task(ref, completion_id)
        return nil unless task

        if order_id = task["order_id"]?.try(&.as_s?)
          unless order_id.empty?
            if result = chat_order_result(order_id)
              task = update_chat_completion_task(task, result)
            end
          end
        end

        id = task["completion_id"]?.try(&.as_s?) || chat_completion_id_for_ref(task["ref"]?.try(&.as_s?) || ref)
        model = task["model"]?.try(&.as_s?) || "workflow/orator"
        status = task["status"]?.try(&.as_s?) || "queued"
        result = task["result"]?.try(&.as_s?) || ""
        content = status == "completed" && !result.empty? ? result : "The task is still running."

        chat_completion_payload(id, model, content, chat_completion_created(task))
      end

      private def workflow_chat_completion_id(snapshot : Ocawe::Workflow::WorkflowRunSnapshot?, workflow_id : String) : String?
        return nil unless workflow_id == "orator"
        return nil unless snapshot

        if state = snapshot.state
          if id = state["completion_id"]?.try(&.as_s?)
            return id unless id.empty?
          end
          if tasks = state["queued_tasks"]?.try(&.as_a?)
            if first = tasks.first?
              if id = first["completion_id"]?.try(&.as_s?)
                return id unless id.empty?
              end
            end
          end
        end

        if output = snapshot.output
          if id = output["completion_id"]?.try(&.as_s?)
            return id unless id.empty?
          end
          if tasks = output["queued_tasks"]?.try(&.as_a?)
            if first = tasks.first?
              if id = first["completion_id"]?.try(&.as_s?)
                return id unless id.empty?
              end
            end
          end
        end
      end

      private def chat_completion_payload(id : String, model : String, content : String, created : Int64)
        {
          "id" => id,
          "object" => "chat.completion",
          "created" => created,
          "model" => model,
          "choices" => [
            {
              "index" => 0,
              "message" => {
                "role" => "assistant",
                "content" => content,
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
      end

      private def chat_completion_task_ref(completion_id : String) : String
        value = completion_id.strip
        return "" unless value.starts_with?("chatcmpl_orator_")
        value = value.sub(/^chatcmpl_orator_/, "")
        value =~ /\A[a-zA-Z0-9_-]+\z/ ? value : ""
      end

      private def load_chat_completion_task(ref : String, completion_id : String)
        path = File.join(chat_completion_task_dir, "#{ref}.json")
        if File.exists?(path)
          task = JSON.parse(File.read(path)).as_h
          return task if chat_completion_task_matches?(task, ref, completion_id)
        end

        Dir.glob(File.join(chat_completion_task_dir, "*.json")).each do |candidate|
          task = JSON.parse(File.read(candidate)).as_h
          return task if chat_completion_task_matches?(task, ref, completion_id)
        end
        nil
      rescue
        nil
      end

      private def chat_completion_task_matches?(task, ref : String, completion_id : String) : Bool
        task["ref"]?.try(&.as_s?) == ref ||
          task["order_id"]?.try(&.as_s?) == ref ||
          task["completion_id"]?.try(&.as_s?) == completion_id
      end

      private def chat_order_result(order_id : String)
        path = File.join(chat_completion_results_dir, "order-#{order_id}.json")
        return nil unless File.exists?(path)

        raw = File.read(path)
        parsed = JSON.parse(raw)
        content = parsed["content"]?.try(&.as_s?) || parsed["answer"]?.try(&.as_s?) || raw
        status = parsed["status"]?.try(&.as_s?) || "completed"
        status = "queued" if chat_fallback_result?(content)
        {content: content.strip, status: status}
      rescue
        nil
      end

      private def update_chat_completion_task(task, result)
        ref = task["ref"]?.try(&.as_s?) || ""
        return task if ref.empty?

        task["status"] = JSON.parse(result[:status].to_json)
        task["result"] = JSON.parse(result[:content].to_json)
        task["updated_at"] = JSON.parse(Time.utc.to_rfc3339.to_json)
        File.write(File.join(chat_completion_task_dir, "#{ref}.json"), task.to_json)
        task
      rescue
        task
      end

      private def chat_completion_created(task) : Int64
        if created = task["created"]?.try(&.as_i64?)
          return created
        end
        if created_at = task["created_at"]?.try(&.as_s?)
          return Time.parse_rfc3339(created_at).to_unix
        end
        Time.utc.to_unix
      rescue
        Time.utc.to_unix
      end

      private def chat_fallback_result?(content : String) : Bool
        text = content.downcase
        text.includes?("did not return an immediate answer") ||
          text.includes?("registered the task") ||
          text.includes?("rotator failed:") ||
          text.includes?("rate limit exceeded")
      end

      private def chat_completion_id_for_ref(ref : String) : String
        "chatcmpl_orator_#{ref}"
      end

      private def chat_completion_task_dir : String
        File.join(chat_completion_results_dir, "tasks")
      end

      private def chat_completion_results_dir : String
        ENV["ORATOR_RESULTS_DIR"]? || ENV["OCAWE_RESULTS_DIR"]? || "/results"
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
