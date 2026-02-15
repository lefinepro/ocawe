# API Reference

OpenAPI snapshot is stored in `docs/api/openapi.json`.

Key endpoints:
- `GET /v1/workflows`
- `GET /v1/tools`
- `GET /v1/skills`
- `GET /v1/agents`
- `GET /v1/agents/{agentId}`
- `POST /v1/agents/{agentId}/generate`
- `POST /v1/skills/{skillId}/execute`
- `POST /v1/chat/completions` (OpenAI-compatible)

Notes:
- Voice and RAG are DSL workflow nodes (`voice`, `rag`), not dedicated startup auto-registered tools.
- Crystal function nodes use snake_case lines and are auto-registered from Crystal config (`AppConfig.settings.functions`). When extra flat params are provided in DSL (for example `model`, `args`), `input_schema` is required.
- Crystal tool functions use `tool snake_case_fn` and must be registered in Crystal config.
- RAG DSL supports Mastra-compatible request keys: `vectorStoreName`, `indexName`, `queryText`, `topK`, `filter`, `operation`.
- Agent frontmatter supports `voice` and `guardrails`; guardrail violations fail workflow runs with `422` (`workflow_error` envelope).
- Agent schema validation can be configured from workflow DSL params (`input_schema`/`output_schema`) and markdown `crystal` schema blocks via `schema_ref("input"|"output")`.
