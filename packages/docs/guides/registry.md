# Registry API (`Cogni::Registry`)

Use `Cogni::Registry` for runtime extension registration.

Supported API:
- `Cogni::Registry.node_kind`
- `Cogni::Registry.resource`

## Register custom NodeKind

```crystal
Cogni::Registry.node_kind("crystal_native") do |_ctx, parameters|
  {
    "status" => JSON.parse("ok".to_json),
    "message" => parameters["message"]? || JSON.parse("none".to_json),
  }
end

workflow = Cogni::Workflow.build("custom")
workflow
  .node_kind(Cogni::NodeKind.new("crystal_native", {
    "message" => JSON.parse("hello".to_json),
  }))
  .commit
```

## Register resource handler

```crystal
Cogni::Registry.resource("resource_ping") do |_ctx, payload|
  {
    "resource_task" => JSON.parse((payload["task"]?.try(&.as_s?) || "none").to_json),
  }
end
```

Resource handlers can be registered from NodeKind handlers and used through runtime resource flow.
