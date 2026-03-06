module ACD
  module Kemal
    class App
      private def mount_health_endpoints
        get "/health" do |env|
          env.response.content_type = "application/json"
          {status: "ok", timestamp: Time.utc.to_s}.to_json
        end
      end
    end
  end
end
