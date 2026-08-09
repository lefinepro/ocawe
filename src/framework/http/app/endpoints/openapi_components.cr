module ACD
  module Kemal
    class App
      private def openapi_components
        {
            "securitySchemes" => {
              "bearerAuth" => {
                "type" => "http",
                "scheme" => "bearer",
              },
            },
            "parameters" => {
              "WorkflowId" => {
                "name" => "workflowId",
                "in" => "path",
                "required" => true,
                "schema" => {"type" => "string"},
              },
              "RunId" => {
                "name" => "runId",
                "in" => "path",
                "required" => true,
                "schema" => {"type" => "string"},
              },
            },
            "responses" => {
              "NotImplemented" => {
                "description" => "Endpoint scaffold is not implemented yet",
                "content" => {
                  "application/json" => {
                    "schema" => {"$ref" => "#/components/schemas/ErrorEnvelope"},
                    "example" => {
                      "error" => {
                        "type" => "not_implemented",
                        "message" => "endpoint pending implementation",
                      },
                    },
                  },
                },
              },
              "NotFound" => {
                "description" => "Resource not found",
                "content" => {
                  "application/json" => {
                    "schema" => {"$ref" => "#/components/schemas/ErrorEnvelope"},
                  },
                },
              },
            },
            "schemas" => {
              "HealthResponse" => {
                "type" => "object",
                "required" => ["status", "timestamp"],
                "properties" => {
                  "status" => {"type" => "string", "example" => "ok"},
                  "timestamp" => {"type" => "string"},
                },
              },
              "WorkflowResponse" => {
                "type" => "object",
                "required" => ["workflow_id", "source_root_type", "workflow_file", "agents", "skills", "tools", "triggers"],
                "properties" => {
                  "workflow_id" => {"type" => "string"},
                  "source_root_type" => {"type" => "string"},
                  "workflow_file" => {"type" => "string"},
                  "agents" => {"type" => "array", "items" => {"type" => "string"}},
                  "skills" => {"type" => "array", "items" => {"type" => "string"}},
                  "tools" => {"type" => "array", "items" => {"type" => "string"}},
                  "default_model" => {"type" => "string", "nullable" => true},
                  "triggers" => {"$ref" => "#/components/schemas/WorkflowTriggers"},
                },
              },
              "WorkflowTriggers" => {
                "type" => "object",
                "description" => "Stored trigger configuration metadata. Configured does not imply active execution.",
                "required" => ["status", "schedule", "trigger_message", "tags"],
                "properties" => {
                  "status" => {"type" => "string", "enum" => ["configured", "not_configured"]},
                  "schedule" => {"type" => "string", "nullable" => true},
                  "trigger_message" => {"type" => "string", "nullable" => true},
                  "tags" => {"type" => "array", "items" => {"type" => "string"}},
                },
              },
              "GeneratedWorkflowCreateRequest" => {
                "type" => "object",
                "additionalProperties" => false,
                "required" => ["name", "prompt"],
                "properties" => {
                  "id" => {"type" => "string", "pattern" => "^[a-z0-9][a-z0-9_-]{0,63}$"},
                  "workflow_id" => {"type" => "string", "description" => "Compatibility alias for id"},
                  "name" => {"type" => "string", "maxLength" => 160},
                  "description" => {"type" => "string", "nullable" => true, "maxLength" => 2000},
                  "prompt" => {"type" => "string", "maxLength" => 65536},
                  "schedule" => {"type" => "string", "nullable" => true},
                  "tag" => {"type" => "string", "nullable" => true},
                  "trigger_message" => {"type" => "string", "nullable" => true},
                  "trigger" => {"type" => "string", "nullable" => true, "description" => "Compatibility alias for trigger_message"},
                  "model" => {"type" => "string", "nullable" => true},
                  "conversation_id" => {"type" => "string", "nullable" => true},
                  "user_id" => {"type" => "string", "nullable" => true},
                  "environment_id" => {"type" => "string", "nullable" => true},
                },
              },
              "GeneratedWorkflowCreateResponse" => {
                "type" => "object",
                "required" => ["status", "workflow_id", "cawfile_path", "cawfile_content", "nodes", "edges", "metadata"],
                "properties" => {
                  "status" => {"type" => "string", "example" => "created"},
                  "workflow_id" => {"type" => "string"},
                  "name" => {"type" => "string"},
                  "conversation_id" => {"type" => "string", "nullable" => true},
                  "user_id" => {"type" => "string", "nullable" => true},
                  "environment_id" => {"type" => "string", "nullable" => true},
                  "cawfile_path" => {"type" => "string", "description" => "Path relative to the generated workflows root"},
                  "cawfile_content" => {"type" => "string"},
                  "nodes" => {"type" => "array", "items" => {"type" => "object"}},
                  "edges" => {"type" => "array", "items" => {"type" => "object"}},
                  "metadata" => {"type" => "object"},
                },
              },
              "GeneratedWorkflowDeleteResponse" => {
                "type" => "object",
                "required" => ["status", "workflow_id", "cawfile_path"],
                "properties" => {
                  "status" => {"type" => "string", "example" => "deleted"},
                  "workflow_id" => {"type" => "string"},
                  "cawfile_path" => {"type" => "string", "description" => "Deleted path relative to the generated workflows root"},
                },
              },
              "ToolItem" => {
                "type" => "object",
                "required" => ["id", "workflow_id"],
                "properties" => {
                  "id" => {"type" => "string"},
                  "workflow_id" => {"type" => "string"},
                },
              },
              "ToolListResponse" => {
                "type" => "object",
                "required" => ["tools"],
                "properties" => {
                  "tools" => {"type" => "array", "items" => {"$ref" => "#/components/schemas/ToolItem"}},
                },
              },
              "SkillItem" => {
                "type" => "object",
                "required" => ["id", "workflow_id", "name", "description", "file_path"],
                "properties" => {
                  "id" => {"type" => "string"},
                  "workflow_id" => {"type" => "string"},
                  "name" => {"type" => "string"},
                  "description" => {"type" => "string"},
                  "file_path" => {"type" => "string"},
                },
              },
              "SkillListResponse" => {
                "type" => "object",
                "required" => ["skills"],
                "properties" => {
                  "skills" => {"type" => "array", "items" => {"$ref" => "#/components/schemas/SkillItem"}},
                },
              },
              "RunListResponse" => {
                "type" => "object",
                "required" => ["runs"],
                "properties" => {
                  "runs" => {"type" => "array", "items" => {"type" => "string"}},
                },
              },
              "ErrorEnvelope" => {
                "type" => "object",
                "required" => ["error"],
                "properties" => {
                  "error" => {
                    "type" => "object",
                    "required" => ["type", "message"],
                    "properties" => {
                      "type" => {"type" => "string"},
                      "message" => {"type" => "string"},
                    },
                  },
                },
              },
            },
        }
      end

      private def swagger_ui_html : String
        <<-HTML
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <title>OcaweCore API Docs</title>
            <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
          </head>
          <body>
            <div id="swagger-ui"></div>
            <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
            <script>
              window.ui = SwaggerUIBundle({
                url: "/openapi.json",
                dom_id: "#swagger-ui"
              });
            </script>
          </body>
        </html>
        HTML
      end
    end
  end
end
