# cogni-agent-functions

Local shard that contains built-in `agent_*` function handlers:

- `agent_codex`
- `agent_cliproxy`
- `agent_opencode`

The main `cogni` runtime consumes these handlers via
`Cogni::Config::DefaultFunctionHandlers`.
