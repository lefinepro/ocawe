# Limits And Notes

Use this page to understand the current boundaries of the framework before building on top of it.

## Current Constraints

- Deterministic runtime behavior is the default design target.
- Trigger endpoints are the canonical invocation layer for workflows, agents, skills, and functions.
- Voice and RAG are workflow node types, not separate runtime products.
- Non-console logger transports may be preserved as metadata even when runtime execution only uses console logging.
- Some operational guides remain in this docs tree, but they are secondary to the framework documentation path.

## Compatibility Notes

- Prefer `Workflow#step(type, id, ...)` for new workflow construction.
- Use `agent_cliproxy`, `agent_codex`, and `agent_opencode` as unified external agent step types.
- Use `Cogni::RegistryApi.node_kind` and `Cogni::RegistryApi.resource` for runtime extension registration.

## Recommended Reading Order

1. [Quickstart](/guides/quickstart)
2. [Core Concepts](/guides/core-concepts)
3. [Workflow Format](/guides/workflow-format)
4. [Registry](/guides/registry)
5. [Examples](/guides/examples)
