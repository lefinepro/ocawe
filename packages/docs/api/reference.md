# API Reference

OpenAPI snapshot is stored in `docs/api/openapi.json`.

Key endpoints:
- `GET /v1/workflows`
- `GET /v1/tools`
- `GET /v1/skills`
- `POST /v1/skills/{skillId}/execute`

Notes:
- Voice and RAG are DSL workflow nodes (`voice`, `rag`), not dedicated startup auto-registered tools.
- `tool_*` remains for explicit Crystal custom function nodes.
- RAG DSL supports Mastra-compatible request keys: `vectorStoreName`, `indexName`, `queryText`, `topK`, `filter`, `operation`.
- Agent frontmatter supports `voice` and `guardrails`; guardrail violations fail workflow runs with `422` (`workflow_error` envelope).
- Agent schema validation can be configured from workflow DSL params (`input_schema`/`output_schema`) and markdown `crystal` schema blocks via `schema_ref("input"|"output")`.
