# full-capabilities bundle

Runnable example for all active `.acd.cr` directives used by the current loader:

- `@[Resources(model: ...)]` (unified resource management for model/skills/tools)
- `agent` (+ `schema_ref("input"|"output")`)
- `skill`
- internal node directives with explicit schemas (`agent_opencode`, `agent_codex`, `agent_cliproxy`)
- `function_name` (registered internal node execution)
- `exec "path_or_inline", runtime: { ... }` (external script execution)
- `voice`
- `rag`
- `suspend`

## Run

```bash
./build/ocawe up --port 4111 --workflows-root ./shards/examples/full-capabilities --fallback-workflows-root ./shards/examples/full-capabilities
```

## API

```bash
curl -s http://localhost:4111/v1/workflows
curl -s -X POST http://localhost:4111/v1/workflows/full-capabilities/runs -H 'content-type: application/json' -d '{"input_data":{"task":"demo"}}'
```
