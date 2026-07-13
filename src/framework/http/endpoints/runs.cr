module ACD
  module Kemal
    class App
      private def mount_run_endpoints
        post "/v1/workflows/:workflowId/runs" do |env|
          workflow_id = env.params.url["workflowId"]
          body = json_body(env)
          start_workflow_run_from_body(env, workflow_id, body)
        end

        get "/v1/workflows/:workflowId/runs" do |env|
          workflow_id = env.params.url["workflowId"]
          status = env.params.query["status"]?
          runs = @workflow_service.list_runs(workflow_id, status)

          env.response.content_type = "application/json"
          {
            "runs" => runs.map { |run|
              {
                "run_id"      => run.run_id,
                "workflow_id" => run.workflow_id,
                "status"      => run.status,
                "updated_at"  => run.updated_at,
              }
            },
          }.to_json
        end

        get "/v1/workflows/:workflowId/scheduler" do |env|
          workflow_id = env.params.url["workflowId"]
          env.response.content_type = "application/json"
          @scheduler.status(workflow_id).to_json
        end

        get "/v1/workflows/:workflowId/runs/:runId" do |env|
          workflow_id = env.params.url["workflowId"]
          run_id = env.params.url["runId"]
          snapshot = @workflow_service.load_snapshot(workflow_id, run_id)

          unless snapshot
            next run_not_found(env, workflow_id, run_id)
          end

          env.response.content_type = "application/json"
          snapshot.to_json
        end

        post "/v1/workflows/:workflowId/runs/:runId/resume" do |env|
          workflow_id = env.params.url["workflowId"]
          run_id = env.params.url["runId"]
          body = json_body(env)
          node = parse_node_selector(body["node"]?)
          wait_for_all = body["wait_for_all_paths"]?.try(&.as_bool?) || false

          result_or_error = resume_workflow_run_from_body(env, workflow_id, run_id, body, node: node, wait_for_all_paths: wait_for_all)
          if result_or_error
            next result_or_error
          end

          run_snapshot_or_ok_json(env, workflow_id, run_id)
        end

        post "/v1/workflows/:workflowId/runs/:runId/restart" do |env|
          workflow_id = env.params.url["workflowId"]
          run_id = env.params.url["runId"]

          result_or_error = with_workflow_errors(env) do
            @workflow_service.restart_run(workflow_id, run_id)
          end
          if result_or_error.is_a?(String)
            next result_or_error
          end

          run_snapshot_or_ok_json(env, workflow_id, run_id)
        end

        post "/v1/workflows/:workflowId/runs/:runId/time-travel" do |env|
          workflow_id = env.params.url["workflowId"]
          run_id = env.params.url["runId"]
          body = json_body(env)
          node = parse_node_selector(body["node"]?)
          unless node
            next time_travel_requires_node(env)
          end

          input_data = body["input_data"]?.try(&.as_h?)
          initial_state = body["initial_state"]?.try(&.as_h?)
          resume_data = body["resume_data"]?.try(&.as_h?)

          result_or_error = with_workflow_errors(env) do
            @workflow_service.time_travel_run(
              workflow_id,
              run_id,
              node: node,
              input_data: input_data,
              initial_state: initial_state,
              resume_data: resume_data,
            )
          end
          if result_or_error.is_a?(String)
            next result_or_error
          end

          run_snapshot_or_ok_json(env, workflow_id, run_id)
        end

        post "/v1/workflows/:workflowId/runs/:runId/cancel" do |env|
          workflow_id = env.params.url["workflowId"]
          run_id = env.params.url["runId"]

          result_or_error = cancel_workflow_run(env, workflow_id, run_id)
          if result_or_error
            next result_or_error
          end

          run_snapshot_or_ok_json(env, workflow_id, run_id)
        end
      end
    end
  end
end
