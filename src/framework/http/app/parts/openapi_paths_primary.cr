module ACD
  module HTTP
    class App
      private def openapi_paths_primary
        {
            "/health" => {
              "get" => {
                "tags" => ["System"],
                "summary" => "Health check",
                "responses" => {
                  "200" => {
                    "description" => "Server health",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/HealthResponse"},
                      },
                    },
                  },
                },
              },
            },
            "/v1/workflows" => {
              "get" => {
                "tags" => ["Workflows"],
                "summary" => "List workflow IDs",
                "responses" => {
                  "200" => {
                    "description" => "Workflow id list",
                    "content" => {
                      "application/json" => {
                        "schema" => {
                          "type" => "array",
                          "items" => {"type" => "string"},
                        },
                      },
                    },
                  },
                },
              },
            },
            "/v1/workflows/{workflowId}" => {
              "get" => {
                "tags" => ["Workflows"],
                "summary" => "Get workflow metadata",
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
                    "description" => "Workflow metadata",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/WorkflowResponse"},
                      },
                    },
                  },
                  "404" => {"$ref" => "#/components/responses/NotFound"},
                },
              },
            },
            "/v1/tools" => {
              "get" => {
                "tags" => ["Tools"],
                "summary" => "List discovered tools",
                "responses" => {
                  "200" => {
                    "description" => "Tool list",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/ToolListResponse"},
                      },
                    },
                  },
                },
              },
            },
            "/v1/mcp/servers" => {
              "get" => {
                "tags" => ["MCP"],
                "summary" => "List configured MCP servers",
                "responses" => {"200" => {"description" => "MCP server list"}},
              },
              "post" => {
                "tags" => ["MCP"],
                "summary" => "Create MCP server",
                "responses" => {"200" => {"description" => "MCP server"}},
              },
            },
            "/v1/mcp/servers/{serverId}" => {
              "get" => {
                "tags" => ["MCP"],
                "summary" => "Get MCP server",
                "responses" => {"200" => {"description" => "MCP server"}, "404" => {"$ref" => "#/components/responses/NotFound"}},
              },
              "patch" => {
                "tags" => ["MCP"],
                "summary" => "Update MCP server",
                "responses" => {"200" => {"description" => "MCP server"}},
              },
              "delete" => {
                "tags" => ["MCP"],
                "summary" => "Delete MCP server",
                "responses" => {"204" => {"description" => "Deleted"}, "404" => {"$ref" => "#/components/responses/NotFound"}},
              },
            },
            "/v1/mcp/servers/{serverId}/reconnect" => {
              "post" => {
                "tags" => ["MCP"],
                "summary" => "Reconnect MCP server",
                "responses" => {"200" => {"description" => "MCP server"}},
              },
            },
            "/v1/mcp/catalog" => {
              "get" => {
                "tags" => ["MCP"],
                "summary" => "List full MCP catalog",
                "responses" => {"200" => {"description" => "MCP catalog"}},
              },
            },
            "/v1/mcp/catalog/tools" => {
              "get" => {
                "tags" => ["MCP"],
                "summary" => "List MCP tools",
                "responses" => {"200" => {"description" => "MCP tool catalog"}},
              },
            },
            "/v1/mcp/catalog/resources" => {
              "get" => {
                "tags" => ["MCP"],
                "summary" => "List MCP resources",
                "responses" => {"200" => {"description" => "MCP resource catalog"}},
              },
            },
            "/v1/mcp/catalog/prompts" => {
              "get" => {
                "tags" => ["MCP"],
                "summary" => "List MCP prompts",
                "responses" => {"200" => {"description" => "MCP prompt catalog"}},
              },
            },
            "/mcp" => {
              "post" => {
                "tags" => ["MCP"],
                "summary" => "MCP JSON-RPC endpoint",
                "responses" => {"200" => {"description" => "JSON-RPC response"}},
              },
            },
            "/v1/skills" => {
              "get" => {
                "tags" => ["Skills"],
                "summary" => "List discovered skills",
                "responses" => {
                  "200" => {
                    "description" => "Skill list",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/SkillListResponse"},
                      },
                    },
                  },
                },
              },
            },
            "/v1/skills/{skillId}" => {
              "get" => {
                "tags" => ["Skills"],
                "summary" => "Get skill metadata",
                "parameters" => [
                  {
                    "name" => "skillId",
                    "in" => "path",
                    "required" => true,
                    "schema" => {"type" => "string"},
                  },
                ],
                "responses" => {
                  "200" => {
                    "description" => "Skill metadata",
                    "content" => {
                      "application/json" => {
                        "schema" => {"$ref" => "#/components/schemas/SkillItem"},
                      },
                    },
                  },
                  "404" => {"$ref" => "#/components/responses/NotFound"},
                },
              },
            },
            "/v1/skills/{skillId}/execute" => {
              "post" => {
                "tags" => ["Skills"],
                "summary" => "Execute skill (scaffold)",
                "parameters" => [
                  {
                    "name" => "skillId",
                    "in" => "path",
                    "required" => true,
                    "schema" => {"type" => "string"},
                  },
                ],
                "responses" => {
                  "200" => {
                    "description" => "Skill execution response",
                    "content" => {
                      "application/json" => {
                        "schema" => {"type" => "object"},
                      },
                    },
                  },
                  "404" => {"$ref" => "#/components/responses/NotFound"},
                },
              },
            },
            "/v1/responses" => {
              "post" => {
                "tags" => ["Compat"],
                "summary" => "OpenAI responses compatibility route",
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
            "/v1/chat/completions" => {
              "post" => {
                "tags" => ["Compat"],
                "summary" => "OpenAI chat completions compatibility route",
                "responses" => {"501" => {"$ref" => "#/components/responses/NotImplemented"}},
              },
            },
        }
      end
    end
  end
end
