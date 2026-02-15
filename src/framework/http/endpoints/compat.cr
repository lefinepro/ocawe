module ACD
  module HTTP
    class App
      private def mount_compat_endpoints
        post "/v1/responses" { |env| not_implemented(env, "responses endpoint pending Kemal integration") }
        post "/v1/chat/completions" { |env| not_implemented(env, "chat/completions endpoint pending Kemal integration") }
      end
    end
  end
end
