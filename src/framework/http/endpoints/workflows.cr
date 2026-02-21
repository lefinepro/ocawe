module ACD
  module HTTP
    class App
      private def mount_workflow_endpoints
        get "/v1/workflows" do |env|
          env.response.content_type = "application/json"
          workflow_ids.to_json
        end

        get "/v1/workflows/:workflowId" do |env|
          workflow_id = env.params.url["workflowId"]
          workflow = workflow_by_id(workflow_id)

          unless workflow
            env.response.status_code = 404
            next({error: {type: "not_found", message: "workflow not found: #{workflow_id}"}}.to_json)
          end
          workflow = workflow.not_nil!

          env.response.content_type = "application/json"
          {
            workflow_id: workflow_id,
            source_root_type: workflow[:source_root_type],
            workflow_file: workflow[:workflow_file],
            agents: workflow[:agents],
            skills: workflow[:skills],
            tools: workflow[:tools],
            default_model: workflow[:default_model],
            logger: workflow[:logger],
            node_loggers: workflow[:node_loggers],
          }.to_json
        end
      end
    end
  end
end
