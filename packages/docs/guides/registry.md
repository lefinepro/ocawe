# Registry API (`Cogni::RegistryApi`)

Use `Cogni::RegistryApi` for runtime extension registration.

Supported API:
- `Cogni::RegistryApi.node_kind`
- `Cogni::RegistryApi.resource`
- `Workflow#step(type, id, ...)` unified node entry

## Register NodeKind

```crystal
Cogni::RegistryApi.node_kind("crystal_native") do |_ctx, parameters|
  {
    "status" => JSON.parse("ok".to_json),
    "message" => parameters["message"]? || JSON.parse("none".to_json),
  }
end

workflow = Cogni::Workflow.build("node-kind")
workflow
  .step(Cogni::NodeKind.new("crystal_native", {
    "message" => JSON.parse("hello".to_json),
  }))
  .commit
```

## Register resource handler

```crystal
Cogni::RegistryApi.resource("resource_ping") do |_ctx, payload|
  {
    "resource_task" => JSON.parse((payload["task"]?.try(&.as_s?) || "none").to_json),
  }
end
```

Resource handlers can be registered from NodeKind handlers and used through runtime resource flow.

## Unified Node Entry

All built-in and external nodes can be created through one entry:

```crystal
workflow = Cogni::Workflow.build("unified")
workflow
  .step("agent", "assistant", prompt: "You are helpful")
  .step("run", "function_name")
  .step("skill", "translator", agent_id: "assistant")
  .step("voice", "voice-step", config: {"voice_operator" => JSON.parse("openai".to_json)})
  .step("rag", "rag-step", config: {"operation" => JSON.parse("query".to_json)})
  .step("suspend", "approval", reason: "human approval")
  .step("agent_cliproxy", "ext-cliproxy", params: {"model" => JSON.parse("qwen3-coder-plus".to_json)})
  .step("agent_codex", "ext-codex")
  .step("agent_opencode", "ext-opencode")
  .commit
```
