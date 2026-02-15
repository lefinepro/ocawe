---
name: "voice-agent"
description: "Voice helper agent"
model: "openai/gpt-4.1-mini"
voice:
  voice_operator: "openai"
  speaker: "alloy"
guardrails:
  input:
    blocked_terms: ["forbidden"]
---

You are a concise voice workflow assistant.

```crystal schema:input
Schema::Types.object({"task" => Schema::Types.of(String)}, strict: false)
```

```crystal schema:output
Schema::Types.object({"last_response" => Schema::Types.of(String)}, strict: false)
```
