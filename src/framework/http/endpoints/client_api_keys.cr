module ACD
  module Kemal
    class App
      private def mount_client_api_key_endpoints
        post "/v1/api-keys" do |env|
          if auth_error = client_api_key_admin_error(env)
            next auth_error
          end
          body = json_body(env)
          workflow_id = body["workflow_id"]?.try(&.as_s?).to_s.strip
          raise "workflow_id is required" if workflow_id.empty?
          label = body["label"]?.try(&.as_s?).to_s.strip
          requested_token = body["token"]?.try(&.as_s?)
          env.response.status_code = 201
          env.response.content_type = "application/json"
          Ocawe::ClientApiKeys.create(workflow_id, label, requested_token).to_json
        rescue ex
          json_error(env, 422, "api_key_error", ex.message || "could not create API key")
        end

        get "/v1/api-keys" do |env|
          if auth_error = client_api_key_admin_error(env)
            next auth_error
          end
          workflow_id = env.params.query["workflow_id"]?
          env.response.content_type = "application/json"
          {"keys" => Ocawe::ClientApiKeys.list(workflow_id)}.to_json
        rescue ex
          json_error(env, 422, "api_key_error", ex.message || "could not list API keys")
        end

        delete "/v1/api-keys/:id" do |env|
          if auth_error = client_api_key_admin_error(env)
            next auth_error
          end
          unless Ocawe::ClientApiKeys.revoke(env.params.url["id"])
            next json_error(env, 404, "not_found", "API key not found or already revoked")
          end
          env.response.status_code = 204
          ""
        rescue ex
          json_error(env, 422, "api_key_error", ex.message || "could not revoke API key")
        end
      end

      private def client_api_key_admin_error(env) : String?
        configured = Ocawe::ClientApiKeys.admin_key
        return json_error(env, 503, "not_configured", "API-key administration is disabled") unless configured

        provided = env.request.headers["Authorization"]?.to_s
        return nil if client_api_key_secure_equals("Bearer #{configured}", provided)

        env.response.headers["WWW-Authenticate"] = "Bearer"
        json_error(env, 401, "unauthorized", "valid admin bearer token is required")
      end

      private def client_api_key_secure_equals(left : String, right : String) : Bool
        return false unless left.bytesize == right.bytesize
        mismatch = 0_u8
        left.bytes.zip(right.bytes) { |a, b| mismatch |= a ^ b }
        mismatch == 0_u8
      end
    end
  end
end
