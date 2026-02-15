# Cogni

Cogni is a Crystal-first framework runtime for workflow bundles, agents, tools, and typed DSL execution.
It includes a production runtime server, a Bun + Svelte playground, and VitePress docs.

This folder (`shards/cogni`) is a standalone nested repository with its own source, CI workflows, specs, and package tooling.

## Why Cogni?

Cogni is designed for teams that want explicit workflow orchestration in Crystal with practical developer tooling.

Key capabilities:

- Crystal workflow runtime with ACD-style executable bundles (`*.acd.cr`)
- Agent + skills + tools composition with local/global discovery
- Voice and RAG usage through workflow DSL patterns
- Guardrails and schema validation support in agent/workflow definitions
- Local playground UI (`packages/playground`) for runtime interaction
- Local docs site (`packages/docs`) with API and text guides

## Get Started

```bash
cd shards/cogni
```

Build the CLI:

```bash
crystal build src/cli/main.cr -o build/cogni
```

Use CLI commands:

```bash
# Build release runtime binary
./build/cogni build --release

# Dev mode: watch workflows/global agents/tools, rebuild and restart
./build/cogni dev --port 4111

# Build + run runtime server
./build/cogni up --port 4111
```

`cogni up` starts only the runtime server. Docs and playground preview servers are separate.

## Packages

### Playground

Path: `shards/cogni/packages/playground`

```bash
cd shards/cogni/packages/playground
bun install
bun run dev
bun run build
```

### Docs

Path: `shards/cogni/packages/docs`

```bash
cd shards/cogni/packages/docs
bun install
bun run dev
bun run build
```

## Project Structure

```text
shards/cogni/
  src/
    cli/                     # cogni CLI (build/dev/up)
    framework/               # runtime framework + HTTP endpoints
    cogni.cr                 # runtime entrypoint
  packages/
    playground/              # Bun + Vite + Svelte + SvelteFlow
    docs/                    # VitePress docs (.vitepress/, guides/, api/)
  shards/examples/           # reference workflow bundles
  spec/                      # Crystal specs
  .github/workflows/         # subrepo CI/CD workflows
```

## Workflow Bundle Format

- Workflow executable: `<workflow-id>.acd.cr`
- Typical bundle layout:
  - `<workflow-id>/<workflow-id>.acd.cr`
  - `<workflow-id>/agents/*.md`
  - `<workflow-id>/skills/*.md`
  - `<workflow-id>/tools/*` (optional)
- Agent frontmatter supports `model`, `voice`, `guardrails`
- Schema validation supports Crystal DSL + schema refs in workflows

## Documentation

Main docs package: `shards/cogni/packages/docs`

Key guides:

- `shards/cogni/packages/docs/guides/tutorial.md`
- `shards/cogni/packages/docs/guides/workflow-format.md`
- `shards/cogni/packages/docs/guides/directory-conventions.md`
- `shards/cogni/packages/docs/api/reference.md`

## CI/CD

This repository has its own GitHub Actions workflows:

- `.github/workflows/cognicore-next-ci.yml`
- `.github/workflows/pages-docs.yml`
- `.github/workflows/release-tag.yml`
- `.github/workflows/deploy.yml`

All workflow commands are subrepo-relative (`packages/*`, `src/*`, `build/*`).

## Mise Tasks

If you use `mise`, tasks are defined in `.mise.toml`:

```bash
cd shards/cogni
mise run cli-build
mise run build
mise run dev
mise run up
mise run playground-build
mise run docs-build
```

## Contributing

Contributions are welcome across runtime, DSL, docs, and playground.

Before opening a PR:

- run Crystal specs
- build playground and docs
- verify workflow bundle conventions remain compatible
