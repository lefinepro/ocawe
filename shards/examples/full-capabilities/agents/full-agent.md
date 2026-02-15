---
description: "Agent covering schema_ref, voice and guardrails"
model: "openapi/qwen3-coder-plus"
voice:
  voice_operator: "openai"
  speaker: "alloy"
guardrails:
  input:
    blocked_terms: ["forbidden"]
---

You are a concise workflow demo agent. Return a short summary.

```crystal schema:input
Schema::Types.object({"task" => Schema::Types.of(String)}, strict: false)
```

```crystal schema:output
Schema::Types.object({"last_response" => Schema::Types.of(String)}, strict: false)
```
