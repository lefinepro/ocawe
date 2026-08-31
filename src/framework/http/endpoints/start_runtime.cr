module ACD
  module Kemal
    class App
      # Small, stable API for the optimized `ocawe start` runtime mode.
      # The legacy `/v1/...` surface remains mounted by `ocawe up`.
      private def mount_start_runtime_endpoints
        post "/run" do |env|
          if auth_error = caw_run_auth_error(env)
            next auth_error
          end
          body = json_body(env)
          workflow_id = body["workflow_id"]?.try(&.as_s?)
          unless workflow_id && !workflow_id.strip.empty?
            next json_error(env, 400, "bad_request", "workflow_id is required")
          end

          start_workflow_run_from_body(env, workflow_id, body)
        end

        post "/stop/:id" do |env|
          if auth_error = caw_run_auth_error(env)
            next auth_error
          end
          body = json_body(env)
          workflow_id = body["workflow_id"]?.try(&.as_s?)
          unless workflow_id && !workflow_id.strip.empty?
            next json_error(env, 400, "bad_request", "workflow_id is required")
          end

          run_id = env.params.url["id"]
          result_or_error = cancel_workflow_run(env, workflow_id, run_id)
          if result_or_error
            next result_or_error
          end

          run_snapshot_or_ok_json(env, workflow_id, run_id)
        end

        get "/metrics" do |env|
          if auth_error = caw_run_auth_error(env)
            next auth_error
          end
          env.response.content_type = "application/json"
          {
            "metrics" => Ocawe::Telemetry.metrics_snapshot.map do |point|
              {
                "name"       => point.name,
                "kind"       => point.kind,
                "value"      => point.value,
                "unit"       => point.unit,
                "attributes" => point.attributes,
                "time_unix_nano" => point.time_unix_nano,
              }
            end,
          }.to_json
        end
      end
    end
  end
end
