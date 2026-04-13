# Cogni

Cogni is a Crystal-first runtime for building deterministic workflow systems with agents, tools, skills, triggers, and HTTP APIs.

Licenses: [ISC](https://spdx.org/licenses/ISC.html) (`LICENSE`) and [0BSD](https://spdx.org/licenses/0BSD.html) (`LICENSE-0BSD`).

## Why Cogni

- Build workflow bundles in Crystal with explicit execution graphs.
- Run the same workflows through CLI triggers or HTTP endpoints.
- Compose agents, external tools, skills, voice flows, and RAG steps in one runtime.
- Extend the runtime through registered node kinds and resources.
- Keep schemas, validation, and workflow behavior explicit and testable.

## Quickstart

Build the CLI:

```bash
crystal build src/cli/main.cr -o build/cogni
```

Start the runtime:

```bash
./build/cogni up --port 4111
```

List workflows:

```bash
curl -sS http://127.0.0.1:4111/v1/workflows | jq
```

Run the Svelte playground:

```bash
cd packages/playground
bun install
bun run dev
```

Run the docs site:

```bash
cd packages/docs
bun install
bun run dev
```

## Core Concepts

### Workflows

Cogni workflows are declared in `.acd.cr` bundles or built programmatically with `Cogni::Workflow.build(...)`. The preferred workflow API is the unified step model:

```crystal
workflow = Cogni::Workflow.build("review")
workflow
  .step("agent", "triage", prompt: "Classify the request")
  .step("exec", "tools/analyze.sh", runtime: {"shell" => JSON.parse("bash".to_json)})
  .step("node_kind", "delegate", node_kind_name: "agent_codex")
  .commit
```

Use `Workflow#step(type, id, ...)` for built-in nodes and external node kinds. For custom node kind instances, use `Workflow#step(Cogni::NodeKind.new(...), id: ...)`.

### Registry Extensions

Extend the runtime through `Cogni::RegistryApi`:

```crystal
Cogni::RegistryApi.node_kind("crystal_native") do |_ctx, attributes|
  {
    "status" => JSON.parse("ok".to_json),
    "message" => attributes["message"]? || JSON.parse("none".to_json),
  }
end

Cogni::RegistryApi.resource("resource_ping") do |_ctx, payload|
  {
    "task" => JSON.parse((payload["task"]?.try(&.as_s?) || "none").to_json),
  }
end
```

Register node kinds only via `Cogni::RegistryApi.node_kind` and resource handlers only via `Cogni::RegistryApi.resource`.

### Built-in External Agent Step Types

External agent nodes are exposed through unified step types:

- `agent_cliproxy`
- `agent_codex`
- `agent_opencode`

These are registered as node kinds and can be used through the unified step model.

## Running Workflows

CLI trigger examples:

```bash
./build/cogni workflow solver task=deploy env=prod
./build/cogni agent code-reviewer --prompt "review this patch"
./build/cogni tool project_healthcheck
./build/cogni support onboarding-check
```

HTTP runtime examples:

- `GET /v1/workflows`
- `GET /v1/workflows/:workflowId`
- `POST /v1/workflows/:workflowId/runs`
- `POST /v1/triggers/workflows/:id`
- `POST /v1/triggers/agents/:id`
- `POST /v1/triggers/skills/:id`
- `POST /v1/triggers/functions/:id`
- `POST /v1/chat/completions`

## Extending The Framework

Cogni is organized around a few extension surfaces:

- declarative runtime: `src/framework/workflows/declarative`
- DSL and schemas: `src/framework/workflows/dsl`
- registry API: `src/framework/registry/api.cr`
- HTTP runtime: `src/framework/http`

The runtime direction is additive and explicit:

- prefer `Workflow#step(type, id, ...)`
- use `agent_cliproxy`, `agent_codex`, and `agent_opencode` as external agent step types
- use `Cogni::NodeKind.new(...)` when you need an explicit node kind object
- keep runtime behavior deterministic

## Examples

Reference bundles live in `shards/examples`:

- `agents-example`
- `skills-example`
- `workflow-example`
- `voice-playground`
- `rag-playground`
- `simple-model-test`
- `full-capabilities`
- `control-flow`
- `config-example`

Run them together:

```bash
./build/cogni up --port 4111 --workflows-root ./shards/examples
```

## Docs Map

- Overview: `packages/docs/index.md`
- Quickstart: `packages/docs/guides/quickstart.md`
- Core concepts: `packages/docs/guides/core-concepts.md`
- Workflow format: `packages/docs/guides/workflow-format.md`
- Registry and extensions: `packages/docs/guides/registry.md`
- Examples: `packages/docs/guides/examples.md`
- API reference: `packages/docs/api/reference.md`

## Current Notes

- The HTTP runtime is the main integration surface; trigger endpoints are the canonical invocation layer.
- Voice and RAG are workflow node types, not separate product areas.
- Some operational guides remain in `packages/docs/guides`, but they are secondary to the core framework docs.
