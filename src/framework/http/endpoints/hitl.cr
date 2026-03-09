module ACD
  module Kemal
    class App
      private def mount_hitl_endpoints
        get "/v1/hitl/runs" do |env|
          runs = @workflow_service.list_runs(nil, "suspended")
          env.response.content_type = "application/json"
          {
            "runs" => runs.map { |run|
              {
                "workflow_id"     => run.workflow_id,
                "run_id"          => run.run_id,
                "resume_labels"   => run.resume_labels || [] of String,
                "suspend_payload" => run.suspend_payload,
                "updated_at"      => run.updated_at,
              }
            },
          }.to_json
        end

        get "/v1/hitl/runs/:workflowId/:runId" do |env|
          workflow_id = env.params.url["workflowId"]
          run_id = env.params.url["runId"]
          snapshot = @workflow_service.load_snapshot(workflow_id, run_id)

          unless snapshot
            next run_not_found(env, workflow_id, run_id)
          end

          env.response.content_type = "application/json"
          {
            "workflow_id"     => snapshot.workflow_id,
            "run_id"          => snapshot.run_id,
            "status"          => snapshot.status,
            "resume_labels"   => snapshot.resume_labels || [] of String,
            "suspend_payload" => snapshot.suspend_payload,
            "state"           => snapshot.state,
          }.to_json
        end

        post "/v1/hitl/runs/:workflowId/:runId/actions" do |env|
          workflow_id = env.params.url["workflowId"]
          run_id = env.params.url["runId"]
          body = json_body(env)
          action = body["action"]?.try(&.as_s?) || ""

          case action
          when "resume"
            result_or_error = resume_workflow_run_from_body(env, workflow_id, run_id, body)
            if result_or_error
              next result_or_error
            end
          when "cancel"
            result_or_error = cancel_workflow_run(env, workflow_id, run_id)
            if result_or_error
              next result_or_error
            end
          else
            next unsupported_hitl_action(env, action)
          end

          run_snapshot_or_ok_json(env, workflow_id, run_id)
        end
      end
    end
  end
end
