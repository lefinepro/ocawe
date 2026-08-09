module OcaweCore
  module API
    class Server
      getter port : Int32

      def initialize(@port : Int32)
      end

      def start
        routes = [
          "POST /v1/responses",
          "POST /v1/chat/completions",
          "GET /v1/chat/completions/:completion_id",
          "GET /v1/workflows",
          "POST /v1/workflows/create",
          "DELETE /v1/workflows/generated/:id",
          "GET /v1/workflows/:workflowId",
          "POST /v1/workflows/:workflowId/runs",
          "GET /v1/workflows/:workflowId/runs",
          "GET /v1/workflows/:workflowId/runs/:runId",
          "POST /v1/workflows/:workflowId/runs/:runId/resume",
          "POST /v1/workflows/:workflowId/runs/:runId/restart",
          "POST /v1/workflows/:workflowId/runs/:runId/time-travel",
          "POST /v1/workflows/:workflowId/runs/:runId/cancel",
          "GET /v1/mcp/servers",
          "POST /v1/mcp/servers",
          "GET /v1/mcp/servers/:serverId",
          "PATCH /v1/mcp/servers/:serverId",
          "DELETE /v1/mcp/servers/:serverId",
          "POST /v1/mcp/servers/:serverId/reconnect",
          "GET /v1/mcp/catalog",
          "GET /v1/mcp/catalog/tools",
          "GET /v1/mcp/catalog/resources",
          "GET /v1/mcp/catalog/prompts",
          "POST /mcp",
          "GET /v1/hitl/runs",
          "GET /v1/hitl/runs/:workflowId/:runId",
          "POST /v1/hitl/runs/:workflowId/:runId/actions",
        ]

        puts "[ocawecore] server scaffold ready on port #{@port}"
        puts "[ocawecore] compatibility routes:"
        routes.each { |route| puts "  - #{route}" }
      end
    end
  end
end
