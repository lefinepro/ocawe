module CogniCore
  module API
    class Server
      getter port : Int32

      def initialize(@port : Int32)
      end

      def start
        routes = [
          "POST /v1/responses",
          "POST /v1/chat/completions",
          "GET /v1/workflows",
          "GET /v1/workflows/:workflowId",
          "POST /v1/workflows/:workflowId/runs",
          "GET /v1/workflows/:workflowId/runs",
          "GET /v1/workflows/:workflowId/runs/:runId",
          "POST /v1/workflows/:workflowId/runs/:runId/resume",
          "POST /v1/workflows/:workflowId/runs/:runId/restart",
          "POST /v1/workflows/:workflowId/runs/:runId/time-travel",
          "POST /v1/workflows/:workflowId/runs/:runId/cancel",
          "GET /v1/hitl/runs",
          "GET /v1/hitl/runs/:workflowId/:runId",
          "POST /v1/hitl/runs/:workflowId/:runId/actions",
        ]

        puts "[cognicore] server scaffold ready on port #{@port}"
        puts "[cognicore] compatibility routes:"
        routes.each { |route| puts "  - #{route}" }
      end
    end
  end
end
