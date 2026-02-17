# Examples

Examples live under `shards/examples` and are designed for direct reuse.

## Run all examples

```bash
./build/cogni up --port 4111 --workflows-root ./shards/examples --fallback-workflows-root ./shards/examples
```

## Bundles

- `agents-example`: agent + model basics
- `skills-example`: skills with agent context
- `workflow-example`: agent + function node + schema refs
- `voice-playground`: voice DSL + voice frontmatter
- `rag-playground`: rag DSL + skill choreography
- `simple-model-test`: model override behavior
- `full-capabilities`: all currently supported `.acd.cr` directives
- `config-example`: Crystal-native `AppConfig` template
- `src/custom_provider_example.cr`: custom provider creation macro + `AI::Client` injection
- `src/control_flow_workflow_example.cr`: programmatic control-flow example (`parallel`, `then`, events) with explicit node schemas

## Notes

- Bare `snake_case` function lines are supported and are auto-registered from `AppConfig.settings.functions` (or can be registered manually via `CogniCore::Workflow.register_function`).
- `tool snake_case_fn` syntax is supported for crystal tool functions and should be registered through `CogniCore::Workflow.register_tool`.
- External tool syntax (`tool "path", runtime: { ... }`) works out of the box when script paths are valid.
- Programmatic workflow DSL (`WorkflowDefinition` API) supports `parallel`, `then`, and event nodes (`wait_for_event`, `send_event`).

## Custom provider macro

Use `CogniCore::AI.create_custom_provider` to generate a provider class:

```crystal
CogniCore::AI.create_custom_provider(
  AcmeProvider,
  "acme",
  "ACME_BASE_URL",
  "ACME_API_KEY",
  "https://acme.example/v1"
)
```

Inject it into `AI::Client`:

```crystal
providers = {
  "acme" => CogniCore::AI::AcmeProvider.new,
} of String => CogniCore::AI::Provider

client = CogniCore::AI::Client.new(providers)
response = client.generate_text("acme/demo-model", "Hello")
```
