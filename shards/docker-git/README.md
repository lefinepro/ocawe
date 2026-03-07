# cogni-docker-git (foundation example)

`shards/docker-git` is a standalone example project that turns docker-git style flows
into Cogni primitives and uses `@[Workspace(...)]` as the primary runtime contract.

## What it demonstrates

- Workflow-level and node-level `@[Workspace(...)]`
- Workspace extension API:
  - `Cogni::RegistryApi.workspace_schema`
  - `Cogni::RegistryApi.workspace_resolver`
  - `Cogni::RegistryApi.workspace_hook`
- Lifecycle flow:
  - `create -> clone -> open -> delete`

## Run

```bash
crystal run shards/docker-git/src/docker_git.cr -- --port 4222
```

Then:

```bash
curl -s http://localhost:4222/v1/workflows
curl -s -X POST http://localhost:4222/v1/workflows/docker-git/runs \
  -H 'content-type: application/json' \
  -d '{"input_data":{"task":"bootstrap workspace"}}'
```

## Notes

- This project is intentionally example-first and should be the migration base for a later core integration.
- Function handlers are currently stubs that model lifecycle outputs; replace them with real Docker/Workspace drivers in the next iteration.
