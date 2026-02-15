module ACD
  module HTTP
    class App
      private def mount_tool_endpoints
        get "/v1/tools" do |env|
          env.response.content_type = "application/json"
          {
            "tools" => tools,
          }.to_json
        end
      end
    end
  end
end
