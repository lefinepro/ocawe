module ACD
  module Kemal
    class App
      private def openapi_document : String
        {
          "openapi" => "3.0.3",
          "info" => {
            "title" => "OcaweCore API",
            "version" => OcaweCore::VERSION,
            "description" => "Current HTTP API surface with scaffolded workflow endpoints.",
          },
          "servers" => [
            {"url" => "http://localhost:#{@port}"},
          ],
          "tags" => [
            {"name" => "System"},
            {"name" => "Workflows"},
            {"name" => "Tools"},
            {"name" => "Skills"},
            {"name" => "Runs"},
            {"name" => "HITL"},
            {"name" => "Compat"},
          ],
          "paths" => openapi_paths_primary.merge(openapi_paths_runs),
          "components" => openapi_components,
        }.to_json
      end
    end
  end
end
