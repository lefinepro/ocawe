---
name: cogni-system
description: Use this skill when working on Cogni runtime, docs, and playground as one system. Covers Crystal endpoints, Svelte playground, VitePress integration, cleanup/refactor, and verification workflows.
---

# Cogni System Skill

## Use When

- A task spans runtime (`src/`), playground (`packages/playground`), and docs (`packages/docs`).
- You need to add or change HTTP APIs and surface them in playground/docs.
- You need cleanup, deduplication, dead-code removal, and repo-wide optimization.

## Workflow

1. Discover current behavior first.
2. Define API contract changes before UI changes.
3. Implement backend endpoints and shared logic refactors.
4. Update playground API client and pages.
5. Update docs routes/navigation and README.
6. Remove dead code and duplicate modules.
7. Run verification commands and fix breakages.

## Constraints

- Preserve existing behavior unless the task explicitly requires changes.
- Prefer shared modules when logic is duplicated in more than one file.
- Keep docs and playground route behavior consistent.
- Keep changes ASCII unless a file already requires unicode.

## Commands

Runtime checks:

```bash
crystal spec
```

Playground checks:

```bash
cd packages/playground
bun run lint
bun run build
```

Docs checks:

```bash
cd packages/docs
bun run build
```

## File Focus

- Runtime HTTP: `src/framework/http/`
- AI providers: `src/framework/cognicore/ai/`
- Playground app: `packages/playground/src/`
- Docs config/content: `packages/docs/.vitepress/` and `packages/docs/`
- Top-level onboarding: `README.md`
