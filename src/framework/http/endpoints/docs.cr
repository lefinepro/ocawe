module ACD
  module Kemal
    class App
      private def mount_docs_endpoints
        get "/openapi.json" do |env|
          env.response.content_type = "application/json"
          openapi_document
        end

        get "/docs" do |env|
          env.response.content_type = "text/html"
          swagger_ui_html
        end
      end
    end
  end
end
