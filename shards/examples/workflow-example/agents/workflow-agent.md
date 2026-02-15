---
name: "Workflow Agent"
description: "Agent for workflow composition example"
model: "openai/gpt-4.1-mini"
voice:
  voice_operator: "openai"
---

Summarize the task briefly.

```crystal schema:input
Schema::Types.object({"task" => Schema::Types.of(String)})
```

```crystal schema:output
Schema::Types.object({"last_response" => Schema::Types.of(String)}, strict: false)
```
