module ACD
  module HTTP
    class App
      private def mount_hitl_endpoints
        get "/v1/hitl/runs" do |env|
          runs = @workflow_service.list_runs(nil, "suspended")
          env.response.content_type = "application/json"
          {
            "runs" => runs.map { |run|
              {
                "workflow_id" => run.workflow_id,
                "run_id" => run.run_id,
                "resume_labels" => run.resume_labels || [] of String,
                "suspend_payload" => run.suspend_payload,
                "updated_at" => run.updated_at,
              }
            },
          }.to_json
        end

        get "/v1/hitl/runs/:workflowId/:runId" do |env|
          workflow_id = env.params.url["workflowId"]
          run_id = env.params.url["runId"]
          snapshot = @workflow_service.load_snapshot(workflow_id, run_id)

          unless snapshot
            env.response.status_code = 404
            env.response.content_type = "application/json"
            next({error: {type: "not_found", message: "run not found: #{workflow_id}/#{run_id}"}}.to_json)
          end

          env.response.content_type = "application/json"
          {
            "workflow_id" => snapshot.workflow_id,
            "run_id" => snapshot.run_id,
            "status" => snapshot.status,
            "resume_labels" => snapshot.resume_labels || [] of String,
            "suspend_payload" => snapshot.suspend_payload,
            "state" => snapshot.state,
          }.to_json
        end

        post "/v1/hitl/runs/:workflowId/:runId/actions" do |env|
          workflow_id = env.params.url["workflowId"]
          run_id = env.params.url["runId"]
          body = json_body(env)
          action = body["action"]?.try(&.as_s?) || ""

          resume_payload = body["resume_data"]?.try(&.as_h?) || body["input"]?.try(&.as_h?) || body.dup
          resume_payload.delete("action")

          case action
          when "resume", "approve"
            result_or_error = with_workflow_errors(env) do
              @workflow_service.resume_run(workflow_id, run_id, resume_data: resume_payload)
            end
            if result_or_error.is_a?(String)
              next result_or_error
            end
          when "cancel"
            result_or_error = with_workflow_errors(env) do
              @workflow_service.cancel_run(workflow_id, run_id)
            end
            if result_or_error.is_a?(String)
              next result_or_error
            end
          else
            env.response.status_code = 400
            env.response.content_type = "application/json"
            next({error: {type: "bad_request", message: "unsupported action: #{action}"}}.to_json)
          end

          snapshot = @workflow_service.load_snapshot(workflow_id, run_id)
          env.response.content_type = "application/json"
          snapshot.try(&.to_json) || {"status" => "ok"}.to_json
        end
      end
    end
  end
end
