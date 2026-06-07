module ACD
  module Kemal
    class App
      private def mount_skill_endpoints
        get "/v1/skills" do |env|
          env.response.content_type = "application/json"
          {
            "skills" => skills,
          }.to_json
        end

        get "/v1/skills/:skillId" do |env|
          skill_id = env.params.url["skillId"]
          skill = skill_by_id(skill_id)

          unless skill
            env.response.status_code = 404
            env.response.content_type = "application/json"
            next({error: {type: "not_found", message: "skill not found: #{skill_id}"}}.to_json)
          end

          env.response.content_type = "application/json"
          skill.to_json
        end

        post "/v1/skills/:skillId/execute" do |env|
          skill_id = env.params.url["skillId"]
          skill = skill_by_id(skill_id)

          unless skill
            env.response.status_code = 404
            env.response.content_type = "application/json"
            next({error: {type: "not_found", message: "skill not found: #{skill_id}"}}.to_json)
          end

          body = json_body(env)
          env.response.content_type = "application/json"
          {
            "skill_id" => skill[:id],
            "workflow_id" => skill[:workflow_id],
            "status" => "ok",
            "result" => {
              "message" => "Skill execution scaffolded in OcaweCore",
              "input" => body,
            },
          }.to_json
        end
      end
    end
  end
end
