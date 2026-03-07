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
- `config-example`: Crystal-native `Cogni::Config::Settings` template
- `src/custom_provider_example.cr`: custom provider creation macro + `AI::Client` injection
- `src/control_flow_workflow_example.cr`: programmatic control-flow example (`parallel`, `then`, events) with explicit node schemas

## Foundation Project: docker-git

`shards/docker-git` is a standalone foundation project that uses `@[Workspace(...)]`
as the main workflow contract and demonstrates workspace extension APIs.

Run:

```bash
crystal run shards/docker-git/src/docker_git.cr -- --port 4222
```

## Notes

- Use `function_name` (for example `agent_codex`) for internal Crystal handlers, and `exec "path_or_inline", runtime: {...}` for external execution.
- Function names are not restricted to snake_case. Collision rule: system function keeps base name, user function gets `:1`, `:2`, etc., with optional explicit aliases.
- Programmatic API exposes `Cogni::Workflow` and can be extended by inheritance.
- Programmatic workflow DSL (`WorkflowDefinition` API) supports `parallel`, `then`, and event nodes (`wait_for_event`, `send_event`).
- Federation MR flow accepts `Create(Ticket)`, `Offer(Ticket)` and direct `Ticket` payloads. MR results are published as ForgeFed-style `Offer` with `object.type=Ticket`, no `object.id`, `object.attributedTo=actor`, HTML `content` and `source` in CommonMark.

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
