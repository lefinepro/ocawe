# Workflow Format (`.acd.cr`)

Cogni workflows use Crystal DSL files with extension `.acd.cr`.

Example:

```crystal
workflow "agents-example" do
  use_model "openapi/qwen3-coder-plus"
  agent "simple-agent"
end
```

## Directives supported by current loader

- `use_model "..."`
- `agent "..."` (+ optional params like `model`, `prompt`, `input_schema`, `output_schema`)
- `skill "..."` (optional `agent` binding)
- `tool tool_*` (registered crystal function)
- `tool "path", runtime: { ... }` (external tool)
- `voice "..."` (optional `config`)
- `rag "..."` (optional `config`)
- `approve "..."` (optional `reason`)
- `custom "..."`

## Agent schema references

```crystal
agent "workflow-agent", input_schema: schema_ref("input"), output_schema: schema_ref("output")
```

`schema_ref("input")` / `schema_ref("output")` resolve markdown `crystal` schema blocks from the agent file.

## Full coverage example

See `shards/examples/full-capabilities/full-capabilities.acd.cr`.
