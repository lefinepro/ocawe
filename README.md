# Cogni

Cogni is a Crystal-first runtime for workflow bundles, agents, tools, and skills.

Licenses: [ISC](https://spdx.org/licenses/ISC.html) (`LICENSE`) and [0BSD](https://spdx.org/licenses/0BSD.html) (`LICENSE-0BSD`).

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

## Docker Compose (solver)

`codex` and other provider CLIs are installed inside the container on demand (no `/root/.nvm` bind and no custom `PATH` env needed).
For auth, mount only `/root/.codex`.

```yaml
services:
  cogni:
    image: cogni:test
    container_name: cogni-solver
    ports:
      - "4111:4111"
    environment:
      - COGNI_BUILD_ARGS=--release
      - COGNI_CONFIG_RCL=/cogni/cogni.config.rcl
    volumes:
      - ./cogni.config.rcl:/cogni/cogni.config.rcl:ro
      - /root/.codex:/root/.codex
    restart: unless-stopped
```

Full compose example file: `docker-compose.solver-full-example.yml`.

Provider credential forwarding workflows:
- `provider-credentials-codex`
- `provider-credentials-claude`
- `provider-credentials-opencode`
- `provider-credentials-qwen`

Start and test:

```bash
docker compose -f docker-compose.solver-full-example.yml up -d --build

curl -sS http://127.0.0.1:4111/v1/workflows | jq

curl -sS -X POST http://127.0.0.1:4111/v1/workflows/provider-credentials-codex/runs \
  -H 'content-type: application/json' \
  -d '{"input":{"content":"run mock credentials check"}}' | jq
```

The flow runs `tools/mock-data.rb` (Ruby), saves a file under `/cogni/.cogni/mock-data`, then runs `agent_codex` through `tools/mock-agent-cli.rb`, which saves a credentials report under `/cogni/.cogni/mock-agent`.

Direct local demo (without HTTP runtime):

```bash
PATH="/tmp/fakebin:$PATH" crystal run scripts/provider_credentials_demo.cr
```

This executes `agent_codex`, `agent_claude_code`, `agent_opencode`, and `agent_qwen` handlers directly, verifies forwarded credential/config paths, and writes:
- mock data file under `./.tmp/mock-data`
- provider reports under `./.tmp/mock-agent`

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

# explicit workflow trigger by id
./build/cogni workflow solver task=deploy env=prod

# agent/function/tool/skill/support triggers
./build/cogni agent code-reviewer --prompt "review this patch"
./build/cogni tool project_healthcheck
./build/cogni support onboarding-check

# alias executable style (workflow id from executable name)
ln -sf ./build/cogni /usr/local/bin/cogni_example_workflow
cogni_example_workflow
```

Workflow trigger CLI calls `POST /v1/triggers/workflows/:id` and sends:
- `input.<key>` from `key=value` args (values parsed as JSON when possible).
- `input.args` from positional args without `=`.

Trigger command mapping:
- `workflow` -> `/v1/triggers/workflows/:id`
- `agent` -> `/v1/triggers/agents/:id`
- `skill`/`support` -> `/v1/triggers/skills/:id`
- `function`/`tool` -> `/v1/triggers/functions/:id`

Use `COGNI_TRIGGER_BASE_URL` or `--base-url` to target a non-default runtime URL.

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
- `POST /actors/{identifier}/inbox` (S2S inbound activities, signature-verified)
- `GET /actors/{identifier}/outbox`
- `POST /actors/{identifier}/outbox`
- `GET /federation/metadata` (reported capabilities + supported FEPs from FEDERATION.md)
- `GET /FEDERATION.md` (repo interoperability manifest)

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
./build/cogni up --port 4111 --workflows-root ./shards/examples
```

## Crystal Configuration

Framework configuration is defined in Crystal code via `src/framework/config/settings.cr`.

Federation defaults:
- Aptok in-process KV and queues are used by default.
- `auto_subscribe` remains supported for startup remote actor tracking.

Alternative config format (RCL) is also supported.
Static config file `./cogni.config.rcl` is auto-loaded when present.

Example `config.rcl`:

```rcl
api = "federation"

federation do
  auto_subscribe = [".col.pub"]
end

datasets do
  adapter = "file"
  file_root = "./.cogni/datasets"
end

workflows do
  preferred_workflows_root = "./workflows"
end
```

Default static file in repo: `cogni.config.rcl`.

`api` supports string or array of strings:
- `"federation"`: ForgeFed-only mode (mounts Aptok ActivityPub routes (`/actors/*`, `/inbox`, WebFinger/NodeInfo) plus health/docs)
- `"classic"`: default runtime APIs (`/v1/*`)
- `"mastra"`: backward-compatible alias for `"classic"`
- `["classic", "federation"]`: enable both groups

Federation persistence:
- Federation state is managed through Aptok KV/queue primitives. The current runtime uses in-process Aptok storage; configure durable Aptok storage when adding a persistent deployment adapter.

Function handler selection via RCL:
- `functions.enabled = ["agent_opencode", "agent_codex", "agent_cliproxy", "agent_claude_code", "agent_qwen"]`
- handlers are optional and available only if external shard `cogni-agent-functions` is connected by the host app

Agent CLI defaults:
- `agent_codex`, `agent_claude_code`, `agent_opencode`, `agent_qwen` can auto-install their CLI on first use.
- `CODEX_BIN` / `CLAUDE_BIN` / `OPENCODE_BIN` / `QWEN_BIN` are optional executable overrides.
- per-provider credentials/config paths can be set in node params (`path_to_credentials`, `path_to_config`, `path_to_config_codex`) or via env.
- federation merge runs (`api=federation`, `activity=merge`) inject strict prompt instructions for `agent_*` to return ForgeFed `Offer(Ticket)` JSON only.

Minimal workflow snippets:

```crystal
workflow "solver-codex" do
  agent_codex, install_policy: "on_demand", args: ["--skip-git-repo-check"], input_schema: Schema::Types.any(), output_schema: Schema::Types.any()
end

workflow "solver-claude" do
  agent_claude_code, install_policy: "on_demand", input_schema: Schema::Types.any(), output_schema: Schema::Types.any()
end

workflow "solver-opencode" do
  agent_opencode, install_policy: "on_demand", input_schema: Schema::Types.any(), output_schema: Schema::Types.any()
end

workflow "solver-qwen" do
  agent_qwen, install_policy: "on_demand", input_schema: Schema::Types.any(), output_schema: Schema::Types.any()
end
```

Minimal workflow snippets:

```crystal
workflow "solver-codex" do
  agent_codex, install_policy: "on_demand", args: ["--skip-git-repo-check"], input_schema: Schema::Types.any(), output_schema: Schema::Types.any()
end

workflow "solver-claude" do
  agent_claude_code, install_policy: "on_demand", input_schema: Schema::Types.any(), output_schema: Schema::Types.any()
end

workflow "solver-opencode" do
  agent_opencode, install_policy: "on_demand", input_schema: Schema::Types.any(), output_schema: Schema::Types.any()
end

workflow "solver-qwen" do
  agent_qwen, install_policy: "on_demand", input_schema: Schema::Types.any(), output_schema: Schema::Types.any()
end
```

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
```

## Testing

```bash
crystal spec
cd packages/playground && bun run lint
cd packages/docs && bun run build
```
