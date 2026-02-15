# Workflow Format (`.acd.cr`)

Cogni workflows use Crystal DSL files with extension `.acd.cr`.

Example:

```crystal
workflow "agents-example" do
  use_model "cliproxyapi/qwen3-coder-plus"
  agent "simple-agent"
end
```

## Directives supported by current loader

- `use_model "..."`
- `agent "..."` (+ optional params like `model`, `prompt`, `input_schema`, `output_schema`)
- `skill "..."` (optional `agent` binding)
- `snake_case_fn_name` (registered crystal function node)
- `snake_case_fn_name, input_schema: ..., output_schema: ...` (optional explicit function schemas)
- `snake_case_fn_name, model: "...", args: [...], input_schema: ..., output_schema: ...` (function node with flat params; `input_schema` required when extra params are set)
- `tool snake_case_fn_name` (registered crystal tool function)
- `tool "path", runtime: { ... }` (external tool)
- `voice "..."` (optional `config`)
- `rag "..."` (optional `config`)
- `approve "..."` (optional `reason`)

## Agent schema references

```crystal
agent "workflow-agent", input_schema: schema_ref("input"), output_schema: schema_ref("output")
```

`schema_ref("input")` / `schema_ref("output")` resolve markdown `crystal` schema blocks from the agent file.

For `agent` and bare `snake_case` function nodes, runtime passes a chained input envelope:

```json
{"input": <previous step output>, "context": {"workflow_id": "...", "run_id": "...", "state": {...}}}
```

If function params are defined in DSL, runtime includes these params as flat fields in the function input envelope.

## Full coverage example

See `shards/examples/full-capabilities/full-capabilities.acd.cr`.
