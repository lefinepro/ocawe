# Core Concepts

Use this page when you need the shortest explanation of how Cogni is organized.

## Workflows

Cogni executes workflows as explicit node graphs. The main authoring format is `.acd.cr`.

Preferred direction:

```crystal
workflow "assistant" do
  agent "planner",
    prompt: "Plan the work"

  skill "translator",
    agent_id: "planner"

  exec "tools/report.sh",
    runtime: {shell: "bash"}

  node_kind "delegate",
    node_kind_name: "agent_codex"
end
```

Use `.acd.cr` for runtime bundles, user workflows, and examples.

Programmatic construction with `Cogni::Workflow.build(...)` remains available for internal framework assembly, tests, and advanced embedding. In that API, `Workflow#step(type, id, ...)` is still the unified entry for built-in and external nodes.

## Node Kinds

Node kinds are runtime handlers registered in Crystal. They are the extension point for custom behavior and for built-in external agent integrations.

External agent node kinds use these step types:

- `agent_cliproxy`
- `agent_codex`
- `agent_opencode`

For explicit NodeKind steps, use `Workflow#step(Cogni::NodeKind.new(...), id: ...)`.

## Registry API

Extend the runtime through `Cogni::RegistryApi`.

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

Important rules:

- Register node kinds only with `Cogni::RegistryApi.node_kind`
- Register resources only with `Cogni::RegistryApi.resource`
- Keep runtime behavior explicit and testable

## Runtime Surfaces

Cogni exposes two main ways to run workflows:

- CLI triggers such as `./build/cogni workflow ...`
- HTTP endpoints such as `POST /v1/workflows/:workflowId/runs`

The trigger API is the canonical invocation layer for workflows, agents, skills, and functions.

## Schemas And Validation

Schemas can be attached from workflow DSL or agent markdown schema blocks. Use them to keep inputs, outputs, and resume payloads explicit.

Related pages:

- [Quickstart](/guides/quickstart)
- [Workflow Format](/guides/workflow-format)
- [Registry](/guides/registry)
- [API Reference](/api/reference)
