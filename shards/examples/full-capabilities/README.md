# full-capabilities bundle

Runnable example for all active `.acd.cr` directives used by the current loader:

- `use_model`
- `agent` (+ `schema_ref("input"|"output")`)
- `skill`
- `tool "path", runtime: { ... }` (external tool)
- `voice`
- `rag`
- `approve`
- `custom`

Also includes syntax hint for crystal tool functions (`tool tool_*`) in comments.

## Run

```bash
./build/cogni up --port 4111 --workflows-root ./shards/examples/full-capabilities --fallback-workflows-root ./shards/examples/full-capabilities
```

## API

```bash
curl -s http://localhost:4111/v1/workflows
curl -s -X POST http://localhost:4111/v1/workflows/full-capabilities/runs -H 'content-type: application/json' -d '{"input_data":{"task":"demo"}}'
```
