# Playground

Ocawe ships a Svelte playground and exposes it as a VitePress custom route at `/playground/`.

## Local Development

```bash
cd packages/playground
pnpm install
pnpm run dev
```

The playground dev server runs on `http://localhost:4173` and proxies `/api` to the runtime server.

## Publish Into Docs Route

Build and mirror the playground into VitePress static assets:

```bash
cd packages/playground
pnpm run build:docs
```

This writes static files to `packages/docs/public/playground`.

When you run docs build:

```bash
cd packages/docs
pnpm run build
```

the docs package automatically refreshes `/playground/` first via `sync:playground`.

## Agent Chat

The playground includes an **Agents** tab powered by:

- `GET /v1/agents`
- `GET /v1/agents/:agentId`
- `POST /v1/agents/:agentId/generate`

It also supports OpenAI-compatible chat completions through `POST /v1/chat/completions`.
