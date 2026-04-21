# Registry And Extensions

Use this page when you need to add runtime behavior to Cogni.

## Public Extension APIs

Cogni’s runtime extension surface is centered on:

- `Cogni::RegistryApi.node_kind`
- `Cogni::RegistryApi.resource`
- `Cogni::RegistryApi.workspace_schema`
- `Cogni::RegistryApi.workspace_resolver`
- `Cogni::RegistryApi.workspace_hook`

Important direction:

- Register node kinds only via `Cogni::RegistryApi.node_kind`
- Register resources only via `Cogni::RegistryApi.resource`
- Prefer `.acd.cr` as the workflow authoring format
- Use `Workflow#step(type, id, ...)` only when you need programmatic construction

## Register A Node Kind

```crystal
Cogni::RegistryApi.node_kind("crystal_native") do |_ctx, attributes|
  {
    "status" => JSON.parse("ok".to_json),
    "message" => attributes["message"]? || JSON.parse("none".to_json),
  }
end
```

Use it from a workflow bundle:

```crystal
workflow "node-kind" do
  node_kind "native-step",
    node_kind_name: "crystal_native",
    node_kind_attributes: {
      "message" => "hello",
    }
end
```

For explicit NodeKind construction in programmatic code, use `Workflow#step(Cogni::NodeKind.new(...), id: ...)`.

## Register A Resource

```crystal
Cogni::RegistryApi.resource("resource_ping") do |_ctx, payload|
  {
    "resource_task" => JSON.parse((payload["task"]?.try(&.as_s?) || "none").to_json),
  }
end
```

Resources are the handler surface for runtime resource flow.

## Workspace Extensions

```crystal
Cogni::RegistryApi.workspace_schema("provider_required") do |workspace|
  raise "workspace.provider required" unless workspace["provider"]?.try(&.as_s?)
end

Cogni::RegistryApi.workspace_resolver do |workspace|
  resolved = JSON.parse(workspace.to_json).as_h
  resolved["resolved"] = JSON.parse(true.to_json)
  resolved
end

Cogni::RegistryApi.workspace_hook("before_node") do |ctx, workspace|
  # Observe resolved workspace before node execution.
end
```

## Unified Step Model

In `.acd.cr`, built-in and external nodes use a consistent directive style:

```crystal
workflow "unified" do
  agent "assistant",
    prompt: "You are helpful"

  exec "tools/tool.sh",
    runtime: {shell: "bash"}

  skill "translator",
    agent_id: "assistant"

  voice "voice-step",
    config: {"voice_operator" => "openai"}

  rag "rag-step",
    config: {"operation" => "query"}

  suspend "approval",
    reason: "human approval"

  node_kind "ext-cliproxy",
    node_kind_name: "agent_cliproxy"

  node_kind "ext-codex",
    node_kind_name: "agent_codex"

  node_kind "ext-opencode",
    node_kind_name: "agent_opencode"
end
```

Related pages:

- [Core Concepts](/guides/core-concepts)
- [Workflow Format](/guides/workflow-format)
- [API Reference](/api/reference)
