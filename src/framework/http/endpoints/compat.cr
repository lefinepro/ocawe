module ACD
  module Kemal
    class App
      CHAT_COMPLETION_TASKS_DATASET = "chat_completion_tasks"

      private def mount_compat_endpoints
        post "/v1/messages" do |env|
          body = json_body(env)
          begin
            raise "streaming Anthropic messages are not supported" if stream_requested?(body)
            request_json = body.to_json
            Ocawe::Translation.detect("/v1/messages", request_json)
            chat_body = Ocawe::Translation.request_as_chat("/v1/messages", request_json)
            completion = build_chat_completion(JSON.parse(chat_body).as_h)
            response = Ocawe::Translation.chat_response_as_anthropic(completion.to_json, request_json)
            env.response.status_code = 200
            env.response.content_type = "application/json"
            response.to_json
          rescue ex
            env.response.status_code = completion_error_status(ex)
            env.response.content_type = "application/json"
            {
              "type"  => "error",
              "error" => {
                "type"    => "invalid_request_error",
                "message" => ex.message || "message request failed",
              },
            }.to_json
          end
        end

        post "/v1/responses" do |env|
          body = json_body(env)
          begin
            chat_body = Ocawe::Translation.request_as_chat("/v1/responses", body.to_json)
            completion = build_chat_completion(JSON.parse(chat_body).as_h)
            response = JSON.parse(Ocawe::Translation.chat_response_as_open_responses(completion.to_json, body.to_json)).as_h
            env.response.status_code = 200
            env.response.content_type = "application/json"
            response.to_json
          rescue ex
            env.response.status_code = completion_error_status(ex)
            env.response.content_type = "application/json"
            {error: {type: "response_error", message: ex.message || "response failed"}}.to_json
          end
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
            "task_id"    => task_id,
            "status"     => "queued",
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
        model = normalize_chat_model(body["model"]?.try(&.as_s?) || FALLBACK_CHAT_MODEL)
        messages = extract_chat_messages(body)
        prompt = chat_prompt_from_messages(messages, body)
        system_message = chat_system_message(messages, body)
        metadata = body["metadata"]?.try(&.as_h?) || {} of String => JSON::Any
        api_key = body["api_key"]?.try(&.as_s?)
        base_url = body["base_url"]?.try(&.as_s?)
        tools = body["tools"]?.try(&.as_a?)
        raw_messages = body["messages"]?.try(&.as_a?)
        files = resolve_file_resources(body)
        metadata["files"] = JSON.parse(files.to_json) unless files.empty?

        workflow_id = model.starts_with?("workflow/") ? model.sub("workflow/", "") : nil

        if workflow_id
          workflow = workflow_by_id(workflow_id)

          unless workflow
            raise "workflow not found: #{workflow_id}"
          end

          # Execute workflow with chat input
          input_data = {
            "prompt"   => JSON.parse(prompt.to_json),
            "messages" => JSON.parse(messages.to_json),
          } of String => JSON::Any
          input_data["system"] = JSON.parse(system_message.to_json) if system_message
          input_data["files"] = JSON.parse(files.to_json) unless files.empty?
          copy_chat_identity_fields(body, input_data)
          resources = files.empty? ? nil : {"files" => JSON.parse(files.to_json)} of String => JSON::Any

          run_result = @workflow_service.start_run(workflow_id, input_data: input_data, resources: resources)
          publish_outbound_federation_output(workflow_id, run_result.output || {} of String => JSON::Any)
          snapshot = @workflow_service.load_snapshot(workflow_id, run_result.run_id)
          output_text = if snap = snapshot
                          workflow_chat_output(snap)
                        else
                          run_result.to_json
                        end
          output_blocks = if snap = snapshot
                            workflow_chat_output_blocks(workflow_id, snap)
                          else
                            [] of JSON::Any
                          end
          now = Time.utc.to_unix
          message = {
            "role"    => JSON.parse("assistant".to_json),
            "content" => JSON.parse(output_text.to_json),
          } of String => JSON::Any
          message["output_blocks"] = JSON.parse(output_blocks.to_json) unless output_blocks.empty?

          return JSON.parse({
            "id"      => "chatcmpl_#{Random::Secure.hex(12)}",
            "object"  => "chat.completion",
            "created" => now,
            "model"   => model,
            "choices" => [
              {
                "index"         => 0,
                "message"       => message,
                "finish_reason" => "stop",
              },
            ],
            "usage" => {
              "prompt_tokens"     => 0,
              "completion_tokens" => 0,
              "total_tokens"      => 0,
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
          "id"      => "chatcmpl_#{Random::Secure.hex(12)}",
          "object"  => "chat.completion",
          "created" => now,
          "model"   => response.model,
          "choices" => [
            {
              "index"         => 0,
              "message"       => message,
              "finish_reason" => finish_reason,
            },
          ],
          "usage" => {
            "prompt_tokens"     => 0,
            "completion_tokens" => 0,
            "total_tokens"      => 0,
          },
        }.to_json).as_h
      end

      private def normalize_chat_model(model : String) : String
        normalized = model.strip
        return "workflow/orator" if normalized == "orator" || normalized == "workflow-orator"
        normalized
      end

      private def copy_chat_identity_fields(source : Ocawe::Workflow::AnyHash, target : Ocawe::Workflow::AnyHash) : Nil
        ["user_actor", "user_handle"].each do |field|
          value = source[field]?.try(&.as_s?)
          target[field] = JSON.parse(value.to_json) if value && !value.strip.empty?
        end
      end

      private def build_open_response(body : Ocawe::Workflow::AnyHash) : Ocawe::Workflow::AnyHash
        chat_body = response_body_as_chat_completion(body)
        completion = build_chat_completion(chat_body)
        completion_json = JSON.parse(completion.to_json)
        output_text = completion_json["choices"][0]["message"]["content"]?.try(&.as_s?) || ""
        model = completion_json["model"]?.try(&.as_s?) || (body["model"]?.try(&.as_s?) || FALLBACK_CHAT_MODEL)
        created = completion_json["created"]?.try(&.as_i64?) || Time.utc.to_unix

        JSON.parse({
          "id"         => "resp_#{Random::Secure.hex(12)}",
          "object"     => "response",
          "created_at" => created,
          "status"     => "completed",
          "model"      => model,
          "output"     => [
            {
              "type"    => "message",
              "role"    => "assistant",
              "content" => [
                {
                  "type" => "output_text",
                  "text" => output_text,
                },
              ],
            },
          ],
          "output_text" => output_text,
        }.to_json).as_h
      end

      private def response_body_as_chat_completion(body : Ocawe::Workflow::AnyHash) : Ocawe::Workflow::AnyHash
        copy = JSON.parse(body.to_json).as_h
        return copy if copy["messages"]?

        messages = [] of Hash(String, JSON::Any)
        if input = copy["input"]?
          content = response_input_text(input)
          messages << {
            "role"    => JSON.parse("user".to_json),
            "content" => JSON.parse(content.to_json),
          } of String => JSON::Any unless content.empty?
        elsif prompt = copy["prompt"]?.try(&.as_s?)
          messages << {
            "role"    => JSON.parse("user".to_json),
            "content" => JSON.parse(prompt.to_json),
          } of String => JSON::Any
        end

        copy["messages"] = JSON.parse(messages.to_json) unless messages.empty?
        copy
      end

      private def response_input_text(input : JSON::Any) : String
        if text = input.as_s?
          return text
        end
        if array = input.as_a?
          return array.compact_map do |entry|
            if str = entry.as_s?
              str
            elsif hash = entry.as_h?
              hash["content"]?.try(&.as_s?) || hash["text"]?.try(&.as_s?) || hash["input_text"]?.try(&.as_s?)
            end
          end.join("\n")
        end
        input.to_json
      end

      private def completion_error_status(ex : Exception) : Int32
        message = ex.message || ""
        return 404 if message.includes?("not found") || message.includes?("unknown workflow")
        422
      end

      private def resolve_file_resources(body : Ocawe::Workflow::AnyHash) : Array(Ocawe::Files::AnyHash)
        ids = [] of String
        collect_file_ids(JSON.parse(body.to_json), ids)
        ids.uniq!
        ids.compact_map do |file_id|
          resource = @file_service.resource(file_id)
          raise "file not found: #{file_id}" unless resource
          resource
        end
      end

      private def collect_file_ids(value : JSON::Any, ids : Array(String)) : Nil
        if hash = value.as_h?
          hash.each do |key, child|
            case key
            when "file_id"
              if file_id = child.as_s?
                ids << file_id if file_id.starts_with?("file_")
              end
            when "file_ids"
              collect_file_id_array(child, ids)
            when "files"
              collect_file_ref_array(child, ids)
            else
              collect_file_ids(child, ids)
            end
          end
        elsif array = value.as_a?
          array.each { |entry| collect_file_ids(entry, ids) }
        end
      end

      private def collect_file_id_array(value : JSON::Any, ids : Array(String)) : Nil
        return unless array = value.as_a?
        array.each do |entry|
          file_id = entry.as_s?
          ids << file_id if file_id && file_id.starts_with?("file_")
        end
      end

      private def collect_file_ref_array(value : JSON::Any, ids : Array(String)) : Nil
        return unless array = value.as_a?
        array.each do |entry|
          if file_id = entry.as_s?
            ids << file_id if file_id.starts_with?("file_")
          elsif hash = entry.as_h?
            if file_id = hash["file_id"]?.try(&.as_s?) || hash["id"]?.try(&.as_s?)
              ids << file_id if file_id.starts_with?("file_")
            else
              collect_file_ids(entry, ids)
            end
          end
        end
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
        error : String? = nil,
      ) : Ocawe::Workflow::AnyHash
        now = Time.utc.to_s
        JSON.parse({
          "id"         => task_id,
          "task_id"    => task_id,
          "status"     => status,
          "request"    => request,
          "result"     => result,
          "error"      => error,
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
        choices = completion_hash["choices"].as_a
        message = choices[0]["message"].as_h
        content = message["content"]?.try(&.as_s?) || ""
        finish_reason_val = choices[0]["finish_reason"]?.try(&.as_s?)

        # First chunk: role
        role_chunk = {
          "id"      => id,
          "object"  => "chat.completion.chunk",
          "created" => created,
          "model"   => model,
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
            "id"      => id,
            "object"  => "chat.completion.chunk",
            "created" => created,
            "model"   => model,
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
              "id"      => id,
              "object"  => "chat.completion.chunk",
              "created" => created,
              "model"   => model,
              "choices" => [
                {
                  "index" => 0,
                  "delta" => {
                    "tool_calls" => [
                      {
                        "index"    => 0,
                        "id"       => tc_id,
                        "type"     => tc_type,
                        "function" => {
                          "name"      => tc_name,
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
            "id"      => id,
            "object"  => "chat.completion.chunk",
            "created" => created,
            "model"   => model,
            "choices" => [
              {
                "index"         => 0,
                "delta"         => {} of String => JSON::Any,
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

      private def workflow_chat_output_blocks(workflow_id : String, snapshot : Ocawe::Workflow::WorkflowRunSnapshot) : Array(JSON::Any)
        data = if output = snapshot.output
                 output
               elsif state = snapshot.state
                 state
               else
                 {} of String => JSON::Any
               end
        blocks = [] of JSON::Any
        if output = snapshot.output
          if direct_blocks = output["output_blocks"]?.try(&.as_a?)
            blocks.concat(direct_blocks)
          end
        end
        blocks.concat(output_ui_blocks(output_ui_template_for_workflow(workflow_id), data))
        blocks
      end
    end
  end
end
