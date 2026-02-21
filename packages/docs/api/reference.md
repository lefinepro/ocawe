# API Reference

OpenAPI snapshot is stored in `docs/api/openapi.json`.

Key endpoints:
- `GET /v1/workflows`
- `POST /v1/workflows/{workflowId}/runs`
- `POST /v1/workflows/{workflowId}/runs/{runId}/resume`
- `POST /v1/triggers/workflows/{id}`
- `POST /v1/triggers/agents/{id}`
- `POST /v1/triggers/skills/{id}`
- `POST /v1/triggers/functions/{id}`
- `GET /v1/tools`
- `GET /v1/skills`
- `GET /v1/agents`
- `GET /v1/agents/{agentId}`
- `POST /v1/agents/{agentId}/generate`
- `POST /v1/skills/{skillId}/execute`
- `POST /v1/chat/completions` (OpenAI-compatible)
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
- `POST /mcp` (MCP JSON-RPC endpoint)

Notes:
- Voice and RAG are DSL workflow nodes (`voice`, `rag`), not dedicated startup auto-registered tools.
- Workflow executable nodes use `run "ref"` in DSL and `run(...)` in workflow API.
- `run` can execute registered functions (`run "name"`), script paths (`run "tools/x.sh", runtime: {...}`), or inline script text (`run "console.log(...)", runtime: {...}`).
- Function registration supports aliases and indexed collision resolution (`name:1`, `name:2`, ...). Base-name resolution prioritizes system functions.
- RAG DSL supports Mastra-compatible request keys: `vectorStoreName`, `indexName`, `queryText`, `topK`, `filter`, `operation`.
- Agent frontmatter supports `voice` and `guardrails`; guardrail violations fail workflow runs with `422` (`workflow_error` envelope).
- Agent schema validation can be configured from workflow DSL params (`input_schema`/`output_schema`) and markdown `crystal` schema blocks via `schema_ref("input"|"output")`.
- Resume validation supports `resume_schema` and `schema_ref("resume")`.
- Runs API supports inline `resources` object in both `POST /runs` and `POST /resume`; runtime merges it into `state["resources"]`.
- Triggers API (`/v1/triggers/*`) is the canonical invocation layer for workflows, agents, skills, and functions.
- `GET /v1/workflows/{workflowId}` includes logger metadata when present: `logger` (workflow default) and `node_loggers` (node overrides from `@[Logger(...)]`).
