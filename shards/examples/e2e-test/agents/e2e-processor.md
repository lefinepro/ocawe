---
description: "E2E test processing agent with full schema and guardrails support"
model: "clipproxyapi/qwen3-coder-model"
guardrails:
  input:
    blocked_terms: ["forbidden", "blocked"]
  output:
    max_length: 5000
---

You are an E2E test processing agent. Your role is to:

1. Accept input tasks and process them
2. Validate input against guardrails
3. Generate structured output responses
4. Support various test scenarios

Always respond with structured, concise output that demonstrates the workflow capabilities.

```crystal schema:input
Schema::Types.object({
  "task" => Schema::Types.of(String),
  "options" => Schema::Types.optional(Schema::Types.object({
    "format" => Schema::Types.optional(Schema::Types.of(String)),
    "verbose" => Schema::Types.optional(Schema::Types.of(Bool))
  }, strict: false))
}, strict: false)
```

```crystal schema:output
Schema::Types.object({
  "result" => Schema::Types.of(String),
  "status" => Schema::Types.of(String),
  "metadata" => Schema::Types.optional(Schema::Types.object({
    "processed_at" => Schema::Types.optional(Schema::Types.of(String)),
    "model_used" => Schema::Types.optional(Schema::Types.of(String))
  }, strict: false))
}, strict: false)
```
