module ACD
  module Kemal
    class App
      private def mount_workflow_endpoints
        get "/v1/workflows" do |env|
          env.response.content_type = "application/json"
          workflow_ids.to_json
        end

        get "/v1/workflows/:workflowId" do |env|
          workflow_id = env.params.url["workflowId"]
          response = workflow_details_response(workflow_id)
          unless response
            next json_error(env, 404, "not_found", "workflow not found: #{workflow_id}")
          end

          env.response.content_type = "application/json"
          response
        end
      end

      private def workflow_details_response(workflow_id : String) : String?
        workflow = workflow_by_id(workflow_id)
        return nil unless workflow

        {
          workflow_id:      workflow_id,
          source_root_type: workflow[:source_root_type],
          workflow_file:    workflow[:workflow_file],
          agents:           workflow[:agents],
          skills:           workflow[:skills],
          tools:            workflow[:tools],
          default_model:    workflow[:default_model],
          logger:           workflow[:logger],
          node_loggers:     workflow[:node_loggers],
          triggers:         workflow_trigger_metadata(workflow_id),
        }.to_json
      end
    end
  end
end
