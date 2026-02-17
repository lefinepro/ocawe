# Cogni Examples (Standalone Crystal Shard)

`shards/examples` is an отдельный Crystal package (`cogni-examples`) with its own `shard.yml`.

## Package layout

- `shard.yml` — shard metadata and local dependency on `cogni`
- `src/cogni_examples.cr` — shard entrypoint
- example workflow bundles (`*.acd.cr`, `agents/`, `skills/`, `tools/`)

## Install as local shard

```yaml
# shard.yml of your project

dependencies:
  cogni-examples:
    path: /absolute/path/to/cogni/shards/examples
```

## Run all examples with Cogni runtime

```bash
./build/cogni up --port 4111 --workflows-root ./shards/examples --fallback-workflows-root ./shards/examples
```

## Bundles and coverage

- `agents-example`: `@[Resources(model: "...")]`, `agent`
- `skills-example`: `agent`, `skill`
- `workflow-example`: `agent`, typed `snake_case` function nodes, `schema_ref`
- `voice-playground`: `voice`, agent `voice`/`guardrails` frontmatter
- `rag-playground`: `rag`, skills + typed validation blocks
- `simple-model-test`: model selection via agent/workflow defaults
- `full-capabilities`: all runnable directives supported by current `.acd.cr` loader
- `config-example`: crystal-native `Cogni::Config::Settings` template
- `src/custom_provider_example.cr`: macro-based custom AI provider definition + client injection
- `src/control_flow_workflow_example.cr`: programmatic control-flow (`parallel`, `then`, events) with explicit input/output schemas

## Single bundle run

```bash
./build/cogni up --port 4111 --workflows-root ./shards/examples/full-capabilities --fallback-workflows-root ./shards/examples/full-capabilities
```

## API smoke

```bash
curl -s http://localhost:4111/v1/workflows
curl -s -X POST http://localhost:4111/v1/workflows/full-capabilities/runs -H 'content-type: application/json' -d '{"input_data":{"task":"demo"}}'
```

## Function registration

`run "function_name"` entries require explicit function registration in bootstrap.
Function names are no longer restricted to snake_case; explicit aliases are supported.

```crystal
CogniCore::Workflow.register_function("agent_custom_step") do |ctx|
  CogniCore::Workflow::AgentResult.new(agent_type: "function", content: "ok")
end

CogniCore::Workflow.register_function("project-healthcheck", alias_name: "healthcheck") do |_ctx|
  {"status" => JSON.parse("ok".to_json)}
end
```
