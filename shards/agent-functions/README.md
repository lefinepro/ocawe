# cogni-agent-functions

Local shard that contains built-in `agent_*` function handlers:

- `agent_codex`
- `agent_cliproxy`
- `agent_opencode`
- `agent_claude_code`
- `agent_qwen`

The main `cogni` runtime consumes these handlers via
`Cogni::Config::DefaultFunctionHandlers`.

Notes:
- CLI binaries are auto-installed on-demand for `agent_codex`, `agent_opencode`, `agent_claude_code`, `agent_qwen`.
- `CODEX_BIN`/`CLAUDE_BIN`/`OPENCODE_BIN`/`QWEN_BIN` are optional overrides, not required.
- Per-provider config/credentials can be passed from workflow params:
  - `path_to_credentials`
  - `path_to_config`
  - provider-specific variants like `path_to_config_codex`.
- In federation runs with `api=lefine` and `activity=merge`, handlers prepend a strict prompt contract:
  - output must be a ForgeFed `Offer(Ticket)` JSON object only (no prose/markdown).

## Workflow examples

```crystal
workflow "solver-codex" do
  agent_codex,
    args: ["--skip-git-repo-check"],
    install_policy: "on_demand",
    input_schema: Schema::Types.any(),
    output_schema: Schema::Types.any()
end

workflow "solver-claude" do
  agent_claude_code,
    install_policy: "on_demand",
    input_schema: Schema::Types.any(),
    output_schema: Schema::Types.any()
end

workflow "solver-opencode" do
  agent_opencode,
    install_policy: "on_demand",
    input_schema: Schema::Types.any(),
    output_schema: Schema::Types.any()
end

workflow "solver-qwen" do
  agent_qwen,
    install_policy: "on_demand",
    input_schema: Schema::Types.any(),
    output_schema: Schema::Types.any()
end
```
