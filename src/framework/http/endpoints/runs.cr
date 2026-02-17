module ACD
  module HTTP
    class App
      private def mount_run_endpoints
        post "/v1/workflows/:workflowId/runs" do |env|
          workflow_id = env.params.url["workflowId"]
          body = json_body(env)
          input_data = body["input_data"]?.try(&.as_h?) || body["input"]?.try(&.as_h?) || body.dup
          resources = body["resources"]?.try(&.as_h?)
          input_data.delete("resources")
          run_id = body["run_id"]?.try(&.as_s?)
          resource_id = body["resource_id"]?.try(&.as_s?)

          result_or_error = with_workflow_errors(env) do
            @workflow_service.start_run(workflow_id, run_id: run_id, resource_id: resource_id, input_data: input_data, resources: resources)
          end
          if result_or_error.is_a?(String)
            next result_or_error
          end
          run_result = result_or_error.as(Cogni::Workflows::Declarative::WorkflowRunResult)

          env.response.status_code = 201
          env.response.content_type = "application/json"
          @workflow_service.load_snapshot(workflow_id, run_result.run_id).try(&.to_json) || run_result.to_json
        end

        get "/v1/workflows/:workflowId/runs" do |env|
          workflow_id = env.params.url["workflowId"]
          status = env.params.query["status"]?
          runs = @workflow_service.list_runs(workflow_id, status)

          env.response.content_type = "application/json"
          {
            "runs" => runs.map { |run|
              {
                "run_id" => run.run_id,
                "workflow_id" => run.workflow_id,
                "status" => run.status,
                "updated_at" => run.updated_at,
              }
            },
          }.to_json
        end

        get "/v1/workflows/:workflowId/runs/:runId" do |env|
          workflow_id = env.params.url["workflowId"]
          run_id = env.params.url["runId"]
          snapshot = @workflow_service.load_snapshot(workflow_id, run_id)

          unless snapshot
            env.response.status_code = 404
            env.response.content_type = "application/json"
            next({error: {type: "not_found", message: "run not found: #{workflow_id}/#{run_id}"}}.to_json)
          end

          env.response.content_type = "application/json"
          snapshot.to_json
        end

        post "/v1/workflows/:workflowId/runs/:runId/resume" do |env|
          workflow_id = env.params.url["workflowId"]
          run_id = env.params.url["runId"]
          body = json_body(env)
          resume_data = body["resume_data"]?.try(&.as_h?) || body["input"]?.try(&.as_h?) || body.dup
          resources = body["resources"]?.try(&.as_h?)
          resume_data.delete("resources")
          node = parse_node_selector(body["node"]?)
          wait_for_all = body["wait_for_all_paths"]?.try(&.as_bool?) || false

          result_or_error = with_workflow_errors(env) do
            @workflow_service.resume_run(workflow_id, run_id, resume_data: resume_data, resources: resources, node: node, wait_for_all_paths: wait_for_all)
          end
          if result_or_error.is_a?(String)
            next result_or_error
          end

          snapshot = @workflow_service.load_snapshot(workflow_id, run_id)
          env.response.content_type = "application/json"
          snapshot.try(&.to_json) || {"status" => "ok"}.to_json
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

          snapshot = @workflow_service.load_snapshot(workflow_id, run_id)
          env.response.content_type = "application/json"
          snapshot.try(&.to_json) || {"status" => "ok"}.to_json
        end

        post "/v1/workflows/:workflowId/runs/:runId/time-travel" do |env|
          workflow_id = env.params.url["workflowId"]
          run_id = env.params.url["runId"]
          body = json_body(env)
          node = parse_node_selector(body["node"]?)
          unless node
            env.response.status_code = 400
            env.response.content_type = "application/json"
            next({error: {type: "bad_request", message: "time-travel requires node"}}.to_json)
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

          snapshot = @workflow_service.load_snapshot(workflow_id, run_id)
          env.response.content_type = "application/json"
          snapshot.try(&.to_json) || {"status" => "ok"}.to_json
        end

        post "/v1/workflows/:workflowId/runs/:runId/cancel" do |env|
          workflow_id = env.params.url["workflowId"]
          run_id = env.params.url["runId"]

          result_or_error = with_workflow_errors(env) do
            @workflow_service.cancel_run(workflow_id, run_id)
          end
          if result_or_error.is_a?(String)
            next result_or_error
          end

          snapshot = @workflow_service.load_snapshot(workflow_id, run_id)
          env.response.content_type = "application/json"
          snapshot.try(&.to_json) || {"status" => "ok"}.to_json
        end
      end
    end
  end
end
