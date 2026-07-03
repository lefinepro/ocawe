module ACD
  module Kemal
    class App
      private def mount_environments_endpoints
        post "/v1/environments/config" do |env|
          body = json_body(env)
          provider = body["provider"]?.try(&.as_s?) || "openai"
          api_key = body["api_key"]?.try(&.as_s?)
          base_url = body["base_url"]?.try(&.as_s?)
          model = body["model"]?.try(&.as_s?)
          cli_name = body["cli"]?.try(&.as_s?)

          unless api_key
            env.response.status_code = 422
            env.response.content_type = "application/json"
            next({error: {type: "config_error", message: "api_key is required"}}.to_json)
          end

          if cli_name
            unless Process.find_executable(cli_name)
              result = system("nix --extra-experimental-features 'nix-command flakes' profile install nixpkgs##{cli_name} 2>&1")
              unless result
                env.response.status_code = 422
                env.response.content_type = "application/json"
                next({error: {type: "config_error", message: "failed to install CLI '#{cli_name}' from nixpkgs"}}.to_json)
              end
            end
          end

          env.response.status_code = 200
          env.response.content_type = "application/json"
          next({status: "ok", provider: provider, cli: cli_name}.to_json)
        end
      end
    end
  end
end
