# Directory Conventions

## Production workflows
- Runtime root: current directory by default, or the directory passed to `ocawe up`
- Root framework file: `Cawfile`
- Bundle layout:
  - `<workflow-id>/Cawfile`
  - `<workflow-id>/<workflow-id>.acd.cr` (legacy fallback)
  - `<workflow-id>/agents/*.md`
  - `<workflow-id>/skills/*.md`
  - `<workflow-id>/tools/*` (optional)

The root `Cawfile` can define `settings`, shared structs, `@[Service]`
workflows, and multiple normal `workflow` blocks. Bundle-local `Cawfile` files
are resolved before `.acd.cr`.

## Agent markdown conventions
- Frontmatter may include `model`, `voice`, and `guardrails`.
- Markdown may include Crystal schema blocks:
  - ```crystal schema:input ... ```
  - ```crystal schema:output ... ```
- Schema blocks are resolved by workflow agent attributes via `schema_ref("input")` and `schema_ref("output")`.

## Global shared assets
- Global agents fallback: `agents/*.md`
- Global tools fallback: `tools/*`

Workflow-local assets take precedence for conflicting ids/paths.

## Examples
- Root: `shards/examples`
- Examples are reference/tutorial assets and are not loaded by default runtime roots.

## Shard app directories
- Playground: `packages/playground`
- Docs: `packages/docs`
