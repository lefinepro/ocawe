# Cogni

Cogni is a Crystal-first runtime for deterministic workflow systems built from agents, tools, skills, triggers, and HTTP APIs.

Licenses: [ISC](https://spdx.org/licenses/ISC.html) (`LICENSE`) and [0BSD](https://spdx.org/licenses/0BSD.html) (`LICENSE-0BSD`).

## What You Can Build

- Workflow bundles with explicit node execution
- Agent and tool orchestration from one runtime
- Voice and RAG flows with typed schema validation
- HTTP-driven workflow execution and trigger-based invocation
- Runtime extensions through registered node kinds and resources

## Quickstart

```bash
crystal build src/cli/main.cr -o build/cogni
./build/cogni up --port 4111
curl -sS http://127.0.0.1:4111/v1/workflows | jq
```

Continue with:

- [Quickstart](/guides/quickstart)
- [Core Concepts](/guides/core-concepts)
- [Workflow Format](/guides/workflow-format)
- [Registry](/guides/registry)
- [Examples](/guides/examples)
- [API Reference](/api/reference)

## Core API Direction

Use the unified workflow step model:

```crystal
workflow = Cogni::Workflow.build("assistant")
workflow
  .step("agent", "planner", prompt: "Plan the next step")
  .step("node_kind", "delegate", node_kind_name: "agent_codex")
  .commit
```

Register runtime extensions only through:

- `Cogni::RegistryApi.node_kind`
- `Cogni::RegistryApi.resource`

## Notes

- Trigger endpoints are the canonical invocation layer.
- Voice and RAG are workflow node types.
- Operational guides remain available in the docs tree but are not part of the main framework learning path.
