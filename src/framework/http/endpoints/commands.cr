module ACD
  module Kemal
    class App
      private def mount_command_endpoints
        get "/v1/commands" do |env|
          env.response.content_type = "application/json"
          {
            "commands" => Ocawe::Command.names.map do |name|
              {
                "id"          => name,
                "name"        => name,
                "command"     => "##{name}",
                "kind"        => "ocawe-command",
                "model_route" => {"new", "execute", "result"}.includes?(name),
              }
            end,
          }.to_json
        end
      end
    end
  end
end
