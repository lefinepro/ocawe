# Cogni Framework Development Agent Guide

## Goal
Develop and evolve Cogni framework internals safely and consistently.

## Scope
- Runtime engine and declarative workflow API
- NodeKind execution model
- Registry surface (`Cogni::Registry.node_kind`, `Cogni::Registry.resource`)
- HTTP runtime endpoints and compatibility behavior
- Type-safe schema/DSL integration

## Core Rules
1. Keep runtime behavior deterministic.
2. Prefer additive API changes; avoid hidden implicit behavior.
3. Preserve error envelope consistency for HTTP APIs.
4. Keep NodeKind execution explicit and testable.
5. Add/update specs with every behavior change.

## Architecture Focus
- Declarative runtime: `src/framework/workflows/declarative`
- DSL/schema: `src/framework/workflows/dsl`
- Registry API: `src/framework/registry/api.cr`
- HTTP app/endpoints: `src/framework/http`

## Change Checklist
1. Update code and types.
2. Update runtime wiring/boot paths.
3. Update docs in `packages/docs/guides`.
4. Add or adjust specs under `spec/`.
5. Validate no stale API names remain.

## API Direction
- For custom steps use `Workflow#step(...)` directly.
- Register custom node kinds only via `Cogni::Registry.node_kind`.
- Register resource handlers only via `Cogni::Registry.resource`.
