# User Tutorial

## 1) Build runtime binary

```bash
crystal build src/cli/main.cr -o build/cogni
```

## 2) Run dev mode and runtime up

```bash
./build/cogni dev --port 4111
./build/cogni up --port 4111
```

`cogni up` runs auto-build and starts only the runtime server.
Docs/playground previews are not part of `up`.

## 3) Explore examples

Example bundles are in `shards/examples`:
- `agents-example`
- `skills-example`
- `workflow-example`
- `voice-playground`
- `rag-playground`
- `simple-model-test`

## 4) Write a typed function node

```crystal
workflow "typed-node-example" do
  input_validate Schema::Types.object({
    "query" => Schema::Types.of(String),
  })

  build_answer
end
```

Register function in `AppConfig.settings.functions` (auto-registered at runtime startup):

```crystal
functions: {
  "build_answer" => ->(ctx : CogniCore::Workflow::NodeContext) {
    q = ctx.input_data["input"]?.try(&.as_h?).try(&.["query"]?).try(&.as_s?) || ""
    CogniCore::Workflow::AgentResult.new(
      agent_type: "function",
      content: "Echo: #{q}",
    )
  },
} of String => CogniCore::Workflow::FunctionHandler
```

## 5) Add agent guardrails + crystal schema blocks

In `agents/<id>.md`:

````markdown
---
description: "Guarded agent"
voice:
  voice_operator: "openai"
guardrails:
  input:
    blocked_terms: ["forbidden"]
---
You are a concise assistant.

```crystal schema:input
Schema::Types.object({"input" => Schema::Types.of(JSON::Any)}, strict: false)
```

```crystal schema:output
Schema::Types.object({"last_response" => Schema::Types.of(String)}, strict: false)
```
````

In workflow `.acd.cr`:

```crystal
agent "guarded-agent", input_schema: schema_ref("input"), output_schema: schema_ref("output")
voice "speak"
```
