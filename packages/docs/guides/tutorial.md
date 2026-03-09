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

Run workflow as CLI command (Trigger API):

```bash
# explicit workflow command
./build/cogni workflow solver task=deploy env=prod

# other trigger kinds
./build/cogni agent code-reviewer --prompt "review this patch"
./build/cogni tool project_healthcheck
./build/cogni support onboarding-check

# alias executable
ln -sf ./build/cogni /usr/local/bin/cogni_example_workflow
cogni_example_workflow
```

## 3) Explore examples

Example bundles are in `shards/examples`:
- `agents-example`
- `skills-example`
- `workflow-example`
- `voice-playground`
- `rag-playground`
- `simple-model-test`

## 4) Register a node kind

```crystal
Cogni::RegistryApi.node_kind("crystal_native") do |_ctx, attributes|
  {
    "status" => JSON.parse("ok".to_json),
    "message" => attributes["message"]? || JSON.parse("none".to_json),
  }
end
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
