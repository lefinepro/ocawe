module ACD
  module Kemal
    class App
      private def json_error(env, status_code : Int32, type : String, message : String) : String
        env.response.status_code = status_code
        env.response.content_type = "application/json"
        {error: {type: type, message: message}}.to_json
      end

      # Remote `ocawe up` sets one process-local bearer token. Keep the
      # default empty so existing local runtimes retain their current API
      # behavior, while a public reverse proxy can protect the Caw endpoints.
      private def caw_run_auth_error(env) : String?
        configured = ENV["OCAWE_CAW_RUN_TOKEN"]?.to_s.strip
        return nil if configured.empty?

        provided = env.request.headers["Authorization"]?.to_s
        expected = "Bearer #{configured}"
        return nil if secure_token_equal?(expected, provided)

        env.response.headers["WWW-Authenticate"] = "Bearer"
        json_error(env, 401, "unauthorized", "valid bearer token is required")
      end

      private def secure_token_equal?(left : String, right : String) : Bool
        return false unless left.bytesize == right.bytesize
        mismatch = 0_u8
        left.bytes.zip(right.bytes) { |a, b| mismatch |= a ^ b }
        mismatch == 0_u8
      end
    end
  end
end
