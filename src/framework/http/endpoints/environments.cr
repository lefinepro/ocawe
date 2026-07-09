module ACD
  module Kemal
    class App
      @@provider_config = {provider: "openai", api_key: "", base_url: "", model: ""}

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
              env.response.status_code = 422
              env.response.content_type = "application/json"
              next({error: {type: "config_error", message: "CLI '#{cli_name}' not found in PATH. Install it in the container image."}}.to_json)
            end
          end

          @@provider_config = {provider: provider, api_key: api_key || "", base_url: base_url || "", model: model || ""}

          env.response.status_code = 200
          env.response.content_type = "application/json"
          next({status: "ok", provider: provider, cli: cli_name}.to_json)
        end
      end

      def self.provider_config
        @@provider_config
      end
    end
  end
end
