module ACD
  module Kemal
    class App
      private def openapi_paths_runs
        {
            "/v1/workflows/{workflowId}/runs" => {
              "post" => {
                "tags" => ["Runs"],
                "summary" => "Start workflow run (scaffold)",
                "parameters" => [
                  {
                    "name" => "workflowId",
                    "in" => "path",
                    "required" => true,
                    "schema" => {"type" => "string"},
                  },
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
              "get" => {
                "tags" => ["Runs"],
                "summary" => "List runs for workflow",
                "parameters" => [
                  {
                    "name" => "workflowId",
                    "in" => "path",
                    "required" => true,
                    "schema" => {"type" => "string"},
                  },
                ],
                "responses" => {
                  "200" => {
                    "description" => "Run id list",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/RunListResponse"},
                      },
                    },
                  },
                },
              },
            },
            "/v1/workflows/{workflowId}/runs/{runId}" => {
              "get" => {
                "tags" => ["Runs"],
                "summary" => "Get run snapshot (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/workflows/{workflowId}/runs/{runId}/resume" => {
              "post" => {
                "tags" => ["Runs"],
                "summary" => "Resume run (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/workflows/{workflowId}/runs/{runId}/restart" => {
              "post" => {
                "tags" => ["Runs"],
                "summary" => "Restart run (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/workflows/{workflowId}/runs/{runId}/time-travel" => {
              "post" => {
                "tags" => ["Runs"],
                "summary" => "Time travel run (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/workflows/{workflowId}/runs/{runId}/cancel" => {
              "post" => {
                "tags" => ["Runs"],
                "summary" => "Cancel run (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/hitl/runs" => {
              "get" => {
                "tags" => ["HITL"],
                "summary" => "List HITL runs",
                "responses" => {
                  "200" => {
                    "description" => "Run id list",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/RunListResponse"},
                      },
                    },
                  },
                },
              },
            },
            "/v1/hitl/runs/{workflowId}/{runId}" => {
              "get" => {
                "tags" => ["HITL"],
                "summary" => "Get HITL run details (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/hitl/runs/{workflowId}/{runId}/actions" => {
              "post" => {
                "tags" => ["HITL"],
                "summary" => "Apply HITL action (scaffold)",
                "parameters" => [
                  {"$ref" => "#/components/parameters/WorkflowId"},
                  {"$ref" => "#/components/parameters/RunId"},
                ],
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
        }
      end
    end
  end
end
