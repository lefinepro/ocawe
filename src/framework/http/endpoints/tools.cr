module ACD
  module Kemal
    class App
      private def mount_tool_endpoints
        get "/v1/tools" do |env|
          merged_tools = tools.map do |tool|
            {
              "id" => tool[:id],
              "workflow_id" => tool[:workflow_id],
            }
          end
          @mcp_manager.list_tools.each do |item|
            merged_tools << {
              "id" => item["canonical_id"]?.try(&.as_s?) || "",
              "workflow_id" => "mcp",
            }
          end

          env.response.content_type = "application/json"
          {
            "tools" => merged_tools,
          }.to_json
        end
      end
    end
  end
end
