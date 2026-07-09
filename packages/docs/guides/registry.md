# Registry API (`Ocawe::RegistryApi`)

Use `Ocawe::RegistryApi` for runtime extension registration.

Supported API:
- `Ocawe::RegistryApi.node_kind`
- `Ocawe::RegistryApi.resource`
- `Ocawe::RegistryApi.workspace_schema`
- `Ocawe::RegistryApi.workspace_resolver`
- `Ocawe::RegistryApi.workspace_hook`
- `Workflow#step(type, id, ...)` unified node entry

## Register NodeKind

```crystal
Ocawe::RegistryApi.node_kind("crystal_native") do |_ctx, attributes|
  {
    "status" => JSON.parse("ok".to_json),
    "message" => attributes["message"]? || JSON.parse("none".to_json),
  }
end

workflow = Ocawe::Workflow.build("node-kind")
workflow
  .step(Ocawe::NodeKind.new("crystal_native", {
    "message" => JSON.parse("hello".to_json),
  }))
  .commit
```

## Register resource handler

```crystal
Ocawe::RegistryApi.resource("resource_ping") do |_ctx, payload|
  {
    "resource_task" => JSON.parse((payload["task"]?.try(&.as_s?) || "none").to_json),
  }
end
```

Resource handlers can be registered from NodeKind handlers and used through runtime resource flow.

## Register workspace extensions

```crystal
Ocawe::RegistryApi.workspace_schema("provider_required") do |workspace|
  raise "workspace.provider required" unless workspace["provider"]?.try(&.as_s?)
end

Ocawe::RegistryApi.workspace_resolver do |workspace|
  resolved = JSON.parse(workspace.to_json).as_h
  resolved["resolved"] = JSON.parse(true.to_json)
  resolved
end

Ocawe::RegistryApi.workspace_hook("before_node") do |ctx, workspace|
  # Observe resolved workspace before node execution.
end
```

## Unified Node Entry

All built-in and external nodes can be created through one entry:

```crystal
workflow = Ocawe::Workflow.build("unified")
workflow
  .step("agent", "assistant", prompt: "You are helpful")
  .step("exec", "tools/tool.sh", runtime: {"shell" => JSON.parse("bash".to_json)})
  .step("skill", "translator", agent_id: "assistant")
  .step("voice", "voice-step", config: {"voice_operator" => JSON.parse("openai".to_json)})
  .step("rag", "rag-step", config: {"operation" => JSON.parse("query".to_json)})
  .step("suspend", "approval", reason: "human approval")
  .step("node_kind", "ext-openai", node_kind_name: "agent_openai", node_kind_attributes: {"model" => JSON.parse("gpt-4.1-mini".to_json)})
  .step("node_kind", "ext-codex", node_kind_name: "agent_codex")
  .step("node_kind", "ext-opencode", node_kind_name: "agent_opencode")
  .commit
```

Built-in federation helper node kinds can be used the same way. Example:

```crystal
workflow = Ocawe::Workflow.build("federation-subscribe")
workflow
  .step("node_kind", "subscribe-default-actor",
    node_kind_name: "forgefed_subscribe",
    node_kind_attributes: {
      "name" => JSON.parse("@oq.col.pub".to_json),
    })
  .commit
```

`forgefed_subscribe` accepts `name` in one of these forms:
- `@domain` -> subscribes to `https://domain/actors/default`
- `@actor@domain` -> subscribes to `https://domain/actors/actor`
- `https://...` -> uses the actor URL directly

For startup-time federation bootstrap, the same resolution path is available in RCL config with `federation.auto_subscribe = ["@oq.col.pub"]`.
