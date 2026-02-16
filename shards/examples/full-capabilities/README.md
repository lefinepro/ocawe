# full-capabilities bundle

Runnable example for all active `.acd.cr` directives used by the current loader:

- `use model:`, `use skill:`, `use tool:` (unified resource management)
- `agent` (+ `schema_ref("input"|"output")`)
- `skill`
- `snake_case` function nodes with explicit schemas (`agent_opencode`, `agent_codex`, `agent_cliproxy`)
- `tool snake_case_fn` (registered crystal tool function)
- `tool "path", runtime: { ... }` (external tool)
- `voice`
- `rag`
- `approve`

## Run

```bash
./build/cogni up --port 4111 --workflows-root ./shards/examples/full-capabilities --fallback-workflows-root ./shards/examples/full-capabilities
```

## API

```bash
curl -s http://localhost:4111/v1/workflows
curl -s -X POST http://localhost:4111/v1/workflows/full-capabilities/runs -H 'content-type: application/json' -d '{"input_data":{"task":"demo"}}'
```
