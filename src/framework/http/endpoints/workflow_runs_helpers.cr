module ACD
  module Kemal
    class App
      private def run_not_found(env, workflow_id : String, run_id : String) : String
        json_error(env, 404, "not_found", "run not found: #{workflow_id}/#{run_id}")
      end

      private def unsupported_hitl_action(env, action : String) : String
        json_error(env, 400, "bad_request", "unsupported action: #{action}")
      end

      private def time_travel_requires_node(env) : String
        json_error(env, 400, "bad_request", "time-travel requires node")
      end

      private def run_snapshot_or_ok_json(env, workflow_id : String, run_id : String) : String
        env.response.content_type = "application/json"
        @workflow_service.load_snapshot(workflow_id, run_id).try(&.to_json) || {"status" => "ok"}.to_json
      end

      private def start_workflow_run_from_body(env, workflow_id : String, body : Ocawe::Workflow::AnyHash) : String
        input_data = body["input_data"]?.try(&.as_h?) || body["input"]?.try(&.as_h?) || body.dup
        resources = body["resources"]?.try(&.as_h?)
        input_data.delete("resources")
        run_id = body["run_id"]?.try(&.as_s?)
        resource_id = body["resource_id"]?.try(&.as_s?)

        if @scheduler.enabled?
          queued_run_id = run_id || "run_#{Random::Secure.hex(12)}"
          status = @scheduler.enqueue(
            Ocawe::Workflow::Scheduler::Job.new(
              workflow_id: workflow_id,
              run_id: queued_run_id,
              resource_id: resource_id,
              input_data: input_data,
              resources: resources,
            )
          )

          env.response.status_code = 202
          env.response.content_type = "application/json"
          return {
            "run_id"          => queued_run_id,
            "workflow_id"     => workflow_id,
            "status"          => "queued",
            "status_url"      => "/v1/workflows/#{workflow_id}/runs/#{queued_run_id}",
            "scheduler"    => status,
          }.to_json
        end

        result_or_error = with_workflow_errors(env) do
          @workflow_service.start_run(workflow_id, run_id: run_id, resource_id: resource_id, input_data: input_data, resources: resources)
        end
        return result_or_error if result_or_error.is_a?(String)

        run_result = result_or_error.as(Ocawe::Workflow::WorkflowRunResult)
        publish_outbound_federation_output(workflow_id, run_result.output || {} of String => JSON::Any)
        env.response.status_code = 201
        env.response.content_type = "application/json"
        @workflow_service.load_snapshot(workflow_id, run_result.run_id).try(&.to_json) || run_result.to_json
      end

      private def resume_workflow_run_from_body(env, workflow_id : String, run_id : String, body : Ocawe::Workflow::AnyHash, node : (String | Array(String) | Nil) = nil, wait_for_all_paths : Bool = false) : (String | Nil)
        resume_data = body["resume_data"]?.try(&.as_h?) || body["input"]?.try(&.as_h?) || body.dup
        resources = body["resources"]?.try(&.as_h?)
        resume_data.delete("action")
        resume_data.delete("resources")

        result_or_error = with_workflow_errors(env) do
          @workflow_service.resume_run(workflow_id, run_id, resume_data: resume_data, resources: resources, node: node, wait_for_all_paths: wait_for_all_paths)
        end
        return result_or_error if result_or_error.is_a?(String)

        nil
      end

      private def run_scheduler_job(job : Ocawe::Workflow::Scheduler::Job) : Nil
        result = @workflow_service.start_run(
          job.workflow_id,
          run_id: job.run_id,
          resource_id: job.resource_id,
          input_data: job.input_data,
          resources: job.resources,
        )
        publish_outbound_federation_output(job.workflow_id, result.output || {} of String => JSON::Any)
      end

      private def cancel_workflow_run(env, workflow_id : String, run_id : String) : (String | Nil)
        result_or_error = with_workflow_errors(env) do
          @workflow_service.cancel_run(workflow_id, run_id)
        end
        return result_or_error if result_or_error.is_a?(String)

        nil
      end
    end
  end
end
