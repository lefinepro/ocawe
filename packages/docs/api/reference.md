# API Reference

Use this page as the high-level map of Cogni’s runtime APIs.

OpenAPI snapshot: `packages/docs/api/openapi.json`

## Workflow Runtime

- `GET /v1/workflows`
- `GET /v1/workflows/{workflowId}`
- `POST /v1/workflows/{workflowId}/runs`
- `POST /v1/workflows/{workflowId}/runs/{runId}/resume`

Use these endpoints when your primary unit is a workflow run.

## Trigger API

- `POST /v1/triggers/workflows/{id}`
- `POST /v1/triggers/agents/{id}`
- `POST /v1/triggers/skills/{id}`
- `POST /v1/triggers/functions/{id}`

The trigger API is the canonical invocation layer for workflows, agents, skills, and functions.

## Catalog And Execution Surfaces

- `GET /v1/tools`
- `GET /v1/skills`
- `GET /v1/agents`
- `GET /v1/agents/{agentId}`
- `POST /v1/agents/{agentId}/generate`
- `POST /v1/skills/{skillId}/execute`

## Compatibility And MCP

- `POST /v1/chat/completions`
- `GET /v1/mcp/servers`
- `POST /v1/mcp/servers`
- `GET /v1/mcp/servers/{serverId}`
- `PATCH /v1/mcp/servers/{serverId}`
- `DELETE /v1/mcp/servers/{serverId}`
- `POST /v1/mcp/servers/{serverId}/reconnect`
- `GET /v1/mcp/catalog`
- `GET /v1/mcp/catalog/tools`
- `GET /v1/mcp/catalog/resources`
- `GET /v1/mcp/catalog/prompts`
- `POST /mcp`

## Important Notes

- Voice and RAG are workflow node types.
- Use `exec "ref", runtime: {...}` for external tools and scripts.
- Use `agent_cliproxy`, `agent_codex`, and `agent_opencode` as the unified external agent step types.
- Agent schema validation supports workflow DSL attributes and markdown schema refs.
- `GET /v1/workflows/{workflowId}` includes workflow logger metadata when present.

Related pages:

- [Workflow API Spec](/api/workflow-api-spec)
- [Trigger API Spec](/api/trigger-api-spec)
- [Core Concepts](/guides/core-concepts)
