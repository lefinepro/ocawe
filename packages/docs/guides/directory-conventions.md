# Directory Conventions

## Production workflows
- Root: `src/workflows`
- Bundle layout:
  - `<workflow-id>/<workflow-id>.acd.cr`
  - `<workflow-id>/agents/*.md`
  - `<workflow-id>/skills/*.md`
  - `<workflow-id>/tools/*` (optional)

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

## Code file line limit
- Maximum: `300` lines per code file.
- Enforcement:
  - Local `pre-push` hook via `jdx/hk` (`hk.pkl`).
  - CI check via `scripts/check-max-lines.sh`.
