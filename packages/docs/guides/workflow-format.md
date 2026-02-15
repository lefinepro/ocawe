# Workflow Format (`.acd.cr`)

Cogni workflows use Crystal DSL files with the extension `.acd.cr`.

Example:

```crystal
workflow "agents-example" do
  use_model "openapi/qwen3-coder-plus"
  agent "simple-agent"
end
```

Supported node directives include:
- `agent "..."`
- `skill "..."`
- `tool tool_*` or `tool "path", runtime: { ... }`
- `voice "..."` (DSL-first voice node)
- `rag "..."` (DSL-first retrieval node)
- `custom "..."`
- `approve "..."`

Voice and RAG are workflow DSL capabilities and do not require startup auto-registration of tool modules.

## Agent Schema Parameters

Agent directives support schema parameters:

```crystal
agent "workflow-agent", input_schema: schema_ref("input"), output_schema: schema_ref("output")
```

`schema_ref("input")` and `schema_ref("output")` resolve markdown `crystal` schema blocks from the selected agent file.
