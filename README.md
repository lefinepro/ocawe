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

`cogni build/dev/up` now auto-bootstrap Crystal when `crystal` is missing by downloading a platform archive into `./.tools/crystal`.
You can control bootstrap with env vars:
- `COGNI_CRYSTAL_VERSION` (default `1.13.3`)
- `COGNI_CRYSTAL_BASE_URL` (default Crystal GitHub releases URL)
- `COGNI_CRYSTAL_FORCE_BOOTSTRAP=1` (force local toolchain even if system `crystal` exists)
- `COGNI_CRYSTAL_VERBOSE=1` (print toolchain version during bootstrap)

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

Federation APIs:
- `POST /federation/follows`
- `GET /federation/following`
- `POST /federation/inbox` (S2S inbound activities, signature-verified)
- `GET /federation/outbox`
- `POST /federation/outbox`

S2S ticket ingestion mode:
- follow remote actor and poll remote `outbox` for `Create(Ticket)` activities
- require HTTP Signatures for federation requests

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

Federation memory defaults:
- `adapter: "memory"`
- `sqlite_path: "./.cogni/federation.sqlite3"`

Alternative config format (RCL) is also supported.
Static config file `./cogni.config.rcl` is auto-loaded when present.

Example `config.rcl`:

```rcl
api = "lefine"

federation do
  adapter = "memory"
  sqlite_path = "./.cogni/federation.sqlite3"
end

datasets do
  adapter = "file"
  file_root = "./.cogni/datasets"
end

workflows do
  preferred_workflows_root = "./src/workflows"
  fallback_workflows_root = "./src/workflows"
end
```

Default static file in repo: `cogni.config.rcl`.

`api` supports string or array of strings:
- `"lefine"`: ForgeFed-only mode (mounts only `/federation/*` plus health/docs)
- `"mastra"`: default runtime APIs (`/v1/*`)
- `["mastra", "lefine"]`: enable both groups

Federation persistence modes:
- `adapter = "memory"` (default): state in process memory (reset on restart)
- `adapter = "sqlite"` (optional): persistent state in SQLite file via `sqlite_path`

Function handler selection via RCL:
- `functions.enabled = ["agent_opencode", "agent_codex", "agent_cliproxy"]`
- handlers are optional and available only if external shard `cogni-agent-functions` is connected by the host app

Optional external handler install in host `shard.yml`:

```yaml
dependencies:
  cogni:
    path: ../cogni
  cogni-agent-functions:
    path: ../cogni/shards/agent-functions
```

Run with RCL:

```bash
./build/cogni up --port 4111 --config-rcl ./config.rcl
```

Or with env:

```bash
COGNI_CONFIG_RCL=./config.rcl ./build/cogni up --port 4111
```

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
mise run hooks-install
mise run check-file-lines
```

## File Size Guardrail

Code files are limited to `300` lines.

- CI enforces this via `./scripts/check-max-lines.sh`.
- Local `pre-push` is enforced via `jdx/hk` (`hk.pkl`).

Install git hooks once:

```bash
mise run hooks-install
```

## CI Syntax Check

Run Crystal syntax/type smoke-check without generating a binary:

```bash
./scripts/check-crystal-syntax.sh
```

## Testing

```bash
crystal spec
cd packages/playground && bun run lint
cd packages/docs && bun run build
```
