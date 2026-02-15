# Cogni Examples

Examples are under `shards/examples` and are prepared for direct reuse.

## Quick run for all examples

```bash
./build/cogni up --port 4111 --workflows-root ./shards/examples --fallback-workflows-root ./shards/examples
```

## Bundles and coverage

- `agents-example`: `use_model`, `agent`
- `skills-example`: `agent`, `skill`
- `workflow-example`: `agent`, `custom`, `schema_ref`
- `voice-playground`: `voice`, agent `voice`/`guardrails` frontmatter
- `rag-playground`: `rag`, skills + typed validation blocks
- `simple-model-test`: model selection via agent/workflow defaults
- `full-capabilities`: all runnable directives supported by current `.acd.cr` loader
- `config-example`: crystal-native `AppConfig` template

## Single bundle run

```bash
./build/cogni up --port 4111 --workflows-root ./shards/examples/full-capabilities --fallback-workflows-root ./shards/examples/full-capabilities
```

## Call API

```bash
curl -s http://localhost:4111/v1/workflows
curl -s -X POST http://localhost:4111/v1/workflows/full-capabilities/runs -H 'content-type: application/json' -d '{"input_data":{"task":"demo"}}'
```

## Crystal tool syntax (`tool tool_*`)

Direct crystal tools are supported by syntax, but require explicit registration in bootstrap:

```crystal
CogniCore::Workflow.register_tool("tool_project_healthcheck") do |_ctx|
  {"status" => JSON.parse("ok".to_json)}
end
```
