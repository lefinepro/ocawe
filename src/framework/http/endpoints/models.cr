module ACD
  module Kemal
    class App
      private def mount_models_endpoints
        get "/v1/models" do |env|
          env.response.content_type = "application/json"
          {
            "object" => "list",
            "data" => available_models.map { |m|
              {
                "id" => m[:id],
                "object" => m[:obj],
                "workflow_id" => m[:workflow_id],
                "name" => m[:name],
                "description" => m[:description],
                "model" => m[:model],
              }
            },
          }.to_json
        end
      end

      private def available_models : Array(NamedTuple(
        id: String,
        obj: String,
        workflow_id: String,
        name: String,
        description: String,
        model: String?,
      ))
        models = [] of NamedTuple(
          id: String,
          obj: String,
          workflow_id: String,
          name: String,
          description: String,
          model: String?,
        )

        # Agents
        agents.each do |a|
          models << {
            id: a[:id],
            obj: "agent",
            workflow_id: a[:workflow_id],
            name: a[:name],
            description: a[:description],
            model: a[:model],
          }
        end

        # Workflows
        workflows.each do |w|
          models << {
            id: w[:id],
            obj: "workflow",
            workflow_id: w[:id],
            name: w[:name],
            description: w[:description],
            model: w[:default_model],
          }
        end

        # Skills
        skills.each do |s|
          models << {
            id: s[:id],
            obj: "skill",
            workflow_id: s[:workflow_id],
            name: s[:name],
            description: s[:description],
            model: nil,
          }
        end

        # Tools
        tools.each do |t|
          models << {
            id: t[:id],
            obj: "tool",
            workflow_id: t[:workflow_id],
            name: t[:name],
            description: t[:description],
            model: nil,
          }
        end

        models
      end
    end
  end
end
