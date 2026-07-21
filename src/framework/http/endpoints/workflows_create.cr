require "../../discovery/generated_workflow_writer"

module ACD
  module Kemal
    class App
      private def mount_workflows_create_endpoints
        post "/v1/workflows/create" do |env|
          if auth_error = generated_workflow_auth_error(env)
            next auth_error
          end

          begin
            raw = read_generated_workflow_body(env)
            request = Discovery::GeneratedWorkflowRequest.parse(raw)
            artifact = create_generated_workflow(request)
            env.response.status_code = 201
            env.response.content_type = "application/json"
            generated_workflow_response(request, artifact)
          rescue ex : Discovery::GeneratedWorkflowValidationError
            json_error(env, 400, "invalid_request", ex.message || "invalid workflow request")
          rescue ex : Discovery::GeneratedWorkflowPayloadTooLargeError
            json_error(env, 413, "payload_too_large", ex.message || "request body is too large")
          rescue ex : Discovery::GeneratedWorkflowConflictError
            json_error(env, 409, "conflict", ex.message || "workflow already exists")
          rescue ex
            STDERR.puts "[ocawecore] workflow creation failed: #{ex.message || ex.class.name}"
            json_error(env, 422, "workflow_creation_error", "failed to create or register workflow")
          end
        end

        delete "/v1/workflows/generated/:id" do |env|
          if auth_error = generated_workflow_auth_error(env)
            next auth_error
          end

          workflow_id = env.params.url["id"]
          begin
            artifact = delete_generated_workflow(workflow_id)
            env.response.status_code = 200
            env.response.content_type = "application/json"
            {
              status:       "deleted",
              workflow_id:  artifact.id,
              cawfile_path: artifact.relative_path,
            }.to_json
          rescue ex : Discovery::GeneratedWorkflowValidationError
            json_error(env, 400, "invalid_request", ex.message || "invalid generated workflow id")
          rescue ex : Discovery::GeneratedWorkflowNotFoundError
            json_error(env, 404, "not_found", ex.message || "generated workflow not found")
          rescue ex : Discovery::GeneratedWorkflowProtectionError
            json_error(env, 409, "protected_workflow", ex.message || "workflow is not managed by the generated workflow API")
          rescue ex
            STDERR.puts "[ocawecore] generated workflow deletion failed: #{ex.message || ex.class.name}"
            json_error(env, 422, "workflow_deletion_error", "failed to delete or unregister generated workflow")
          end
        end

        get "/v1/nodes" do |env|
          env.response.content_type = "application/json"
          [
            {kind: "agent", label: "Agent", fields: [{key: "prompt", type: "text", required: false}, {key: "model", type: "text", required: false}]},
            {kind: "exec", label: "Exec", fields: [{key: "ref", type: "text", required: true}, {key: "runtime", type: "text", required: false}]},
            {kind: "voice", label: "Voice", fields: [{key: "config", type: "text", required: false}]},
            {kind: "rag", label: "RAG", fields: [{key: "config", type: "text", required: false}]},
            {kind: "suspend", label: "Suspend", fields: [{key: "reason", type: "text", required: false}]},
            {kind: "skill", label: "Skill", fields: [{key: "skill", type: "text", required: true}]},
            {kind: "parallel", label: "Parallel", fields: [] of NamedTuple(key: String, type: String, required: Bool)},
            {kind: "then", label: "Then", fields: [] of NamedTuple(key: String, type: String, required: Bool)},
            {kind: "while_do", label: "While", fields: [{key: "condition", type: "text", required: true}, {key: "max_iterations", type: "number", required: false}]},
            {kind: "until_do", label: "Until", fields: [{key: "condition", type: "text", required: true}, {key: "max_iterations", type: "number", required: false}]},
            {kind: "loop_do", label: "Loop", fields: [{key: "max_iterations", type: "number", required: false}]},
            {kind: "foreach", label: "ForEach", fields: [] of NamedTuple(key: String, type: String, required: Bool)},
            {kind: "wait_for_event", label: "Wait for event", fields: [{key: "event", type: "text", required: true}]},
            {kind: "send_event", label: "Send event", fields: [{key: "event", type: "text", required: true}]},
            {kind: "sleep", label: "Sleep", fields: [{key: "duration", type: "text", required: true}]},
            {kind: "sleep_until", label: "Sleep until", fields: [{key: "time", type: "text", required: true}]},
          ].to_json
        end
      end

      private def generated_workflow_auth_error(env) : String?
        configured_key = ENV["OCAWE_API_KEY"]?.try(&.strip)
        unless configured_key && !configured_key.empty?
          return json_error(env, 503, "not_configured", "generated workflow API is disabled")
        end

        expected = "Bearer #{configured_key}"
        provided = env.request.headers["Authorization"]?.to_s
        return nil if constant_time_equals?(expected, provided)

        env.response.headers["WWW-Authenticate"] = "Bearer"
        json_error(env, 401, "unauthorized", "valid bearer token is required")
      end

      private def read_generated_workflow_body(env) : String
        max_bytes = Discovery::GeneratedWorkflowRequest::MAX_BODY_BYTES
        if content_length = env.request.headers["Content-Length"]?.try(&.to_i64?)
          if content_length > max_bytes
            raise Discovery::GeneratedWorkflowPayloadTooLargeError.new("request body exceeds #{max_bytes} bytes")
          end
        end

        body = env.request.body
        return "" unless body

        output = IO::Memory.new
        buffer = Bytes.new(8 * 1024)
        total = 0
        loop do
          count = body.read(buffer)
          break if count == 0
          total += count
          if total > max_bytes
            raise Discovery::GeneratedWorkflowPayloadTooLargeError.new("request body exceeds #{max_bytes} bytes")
          end
          output.write(buffer[0, count])
        end
        output.to_s
      end

      private def create_generated_workflow(
        request : Discovery::GeneratedWorkflowRequest,
      ) : Discovery::GeneratedWorkflowArtifact
        @workflow_creation_lock.synchronize do
          if @locator.resolve?(request.id)
            raise Discovery::GeneratedWorkflowConflictError.new("workflow already exists: #{request.id}")
          end

          artifact = @generated_workflow_writer.create(request, known_ids: workflow_ids)
          begin
            reload_cache!
            unless workflow_by_id(request.id)
              raise "generated workflow was not registered: #{request.id}"
            end
          rescue ex
            @generated_workflow_writer.rollback(artifact)
            begin
              reload_cache!
            rescue
            end
            raise ex
          end
          artifact
        end
      end

      private def delete_generated_workflow(
        workflow_id : String,
      ) : Discovery::GeneratedWorkflowDeletionArtifact
        @workflow_creation_lock.synchronize do
          artifact = @generated_workflow_writer.stage_delete(workflow_id)
          begin
            reload_cache!
            if current = workflow_by_id(workflow_id)
              if current[:source_root_type] == "generated"
                raise "generated workflow remained registered after deletion: #{workflow_id}"
              end
            end
            @generated_workflow_writer.commit_delete(artifact)
          rescue ex
            begin
              @generated_workflow_writer.rollback_delete(artifact)
            rescue rollback_ex
              STDERR.puts "[ocawecore] generated workflow deletion rollback failed: #{rollback_ex.message || rollback_ex.class.name}"
              raise rollback_ex
            end

            begin
              reload_cache!
            rescue restore_ex
              STDERR.puts "[ocawecore] workflow cache restore after deletion failed: #{restore_ex.message || restore_ex.class.name}"
            end
            raise ex
          end
          artifact
        end
      end

      private def generated_workflow_response(
        request : Discovery::GeneratedWorkflowRequest,
        artifact : Discovery::GeneratedWorkflowArtifact,
      ) : String
        config = {
          "prompt" => JSON.parse(request.prompt.to_json),
        } of String => JSON::Any
        config["model"] = JSON.parse(request.model.to_json) if request.model

        assistant_node = {
          "id"       => JSON.parse("assistant".to_json),
          "type"     => JSON.parse("agent".to_json),
          "kind"     => JSON.parse("agent".to_json),
          "label"    => JSON.parse(request.name.to_json),
          "position" => JSON.parse({"x" => 0, "y" => 0}.to_json),
          "config"   => JSON.parse(config.to_json),
        } of String => JSON::Any
        output_node = {
          "id"       => JSON.parse("output".to_json),
          "type"     => JSON.parse("output".to_json),
          "kind"     => JSON.parse("output".to_json),
          "label"    => JSON.parse("Output".to_json),
          "position" => JSON.parse({"x" => 320, "y" => 0}.to_json),
          "config"   => JSON.parse("{}"),
          "implicit" => JSON.parse(true.to_json),
        } of String => JSON::Any
        nodes = [assistant_node, output_node]
        edges = [JSON.parse({
          "id"       => "assistant-output",
          "source"   => "assistant",
          "target"   => "output",
          "type"     => "smoothstep",
          "animated" => true,
        }.to_json)]

        {
          status:          "created",
          workflow_id:     request.id,
          name:            request.name,
          description:     request.description,
          conversation_id: request.conversation_id,
          user_id:         request.user_id,
          environment_id:  request.environment_id,
          cawfile_path:    artifact.relative_path,
          path:            artifact.relative_path,
          cawfile_content: artifact.content,
          nodes:           nodes,
          edges:           edges,
          canvas:          {nodes: nodes, edges: edges},
          metadata:        request.metadata,
        }.to_json
      end
    end
  end
end
