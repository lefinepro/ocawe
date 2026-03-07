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
