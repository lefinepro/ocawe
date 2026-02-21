# Cogni

Cogni is a Crystal-first runtime for workflow bundles, agents, tools, and skills.

It includes:
- A production-oriented HTTP runtime server.
- A Svelte playground for workflows, tools, skills, and agent chat.
- VitePress docs with a custom `/playground/` route.

## Why Cogni

- Crystal workflow runtime with ACD-style bundles (`*.acd.cr`).
- Agent + skill + tool discovery from workflow directories.
- Voice and RAG patterns through workflow DSL.
- Schema validation and guardrails in agent/workflow execution.
- OpenAI-compatible chat completions endpoint support.

## Quickstart

Build CLI:

```bash
crystal build src/cli/main.cr -o build/cogni
```

Run runtime server:

```bash
./build/cogni up --port 4111
```

Run playground:

```bash
cd packages/playground
bun install
bun run dev
```

Run docs:

```bash
cd packages/docs
bun install
bun run dev
```

## CLI Commands

```bash
./build/cogni build --release
./build/cogni dev --port 4111
./build/cogni up --port 4111
```

## Runtime APIs

Primary APIs:
- `GET /v1/workflows`
- `POST /v1/workflows/:workflowId/runs`
- `GET /v1/tools`
- `GET /v1/skills`
- `GET /v1/agents`
- `POST /v1/agents/:agentId/generate`
- `GET /v1/mcp/servers`
- `POST /v1/mcp/servers`
- `GET /v1/mcp/catalog`
- `POST /mcp`

Compatibility:
- `POST /v1/chat/completions`

## Project Structure

```text
src/
  cli/                     # cogni CLI (build/dev/up)
  framework/               # runtime framework + HTTP endpoints
packages/
  playground/              # Svelte playground (Vite + Bun)
  docs/                    # VitePress docs and static playground route
shards/examples/           # reference workflow bundles
spec/                      # Crystal specs
```

## Examples

See `shards/examples`:
- `agents-example`
- `skills-example`
- `workflow-example`
- `rag-playground`
- `voice-playground`
- `simple-model-test`
- `full-capabilities`
- `config-example` (Crystal config template)

Run all examples:

```bash
./build/cogni up --port 4111 --workflows-root ./shards/examples --fallback-workflows-root ./shards/examples
```

## Crystal Configuration

Framework configuration is defined in Crystal code via `src/framework/config/settings.cr`.

Template example:
- `shards/examples/config-example/app_config.cr`

## Docs Playground Route

The docs site exposes the playground at `/playground/`.

Build mirrored playground assets:

```bash
cd packages/playground
bun run build:docs
```

Then build docs:

```bash
cd packages/docs
bun run build
```

## Development Tasks (mise)

```bash
mise run cli-build
mise run up
mise run playground-build
mise run docs-build
```

## Testing

```bash
crystal spec
cd packages/playground && bun run lint
cd packages/docs && bun run build
```
