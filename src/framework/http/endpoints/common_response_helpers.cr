module ACD
  module Kemal
    class App
      private def json_error(env, status_code : Int32, type : String, message : String) : String
        env.response.status_code = status_code
        env.response.content_type = "application/json"
        {error: {type: type, message: message}}.to_json
      end
    end
  end
end
