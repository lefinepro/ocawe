# Cogni

Crystal-first runtime for workflows, agents, triggers, and skills.

## What You Can Build

- Agent-driven workflows with explicit graph execution.
- Function/script and skill orchestration from workflow bundles.
- Voice and RAG workflows with typed schema validation.
- Local playground-driven development with runtime APIs.

## Quickstart

```bash
crystal build src/cli/main.cr -o build/cogni
./build/cogni up --port 4111
```

Start the Svelte playground:

```bash
cd packages/playground
bun install
bun run dev
```

Open docs and playground route:

- Docs: `http://localhost:5173/`
- Playground route: `http://localhost:5173/playground/`

## Next Steps

- Tutorial: `/guides/tutorial`
- Workflow format: `/guides/workflow-format`
- API reference: `/api/reference`
- Workflow API spec: `/api/workflow-api-spec`
- Trigger API spec: `/api/trigger-api-spec`
