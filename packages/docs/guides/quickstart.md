# Quickstart

Use this page when you want the shortest path from checkout to a running Cogni runtime.

## Build The CLI

```bash
crystal build src/cli/main.cr -o build/cogni
```

## Start The Runtime

```bash
./build/cogni up --port 4111
```

The runtime starts the HTTP server and loads workflows from the current workspace.

## Author A Workflow Bundle

Create a `.acd.cr` file in your workspace:

```crystal
workflow "hello" do
  agent "assistant",
    model: "openai/gpt-4.1",
    prompt: "Reply briefly and clearly"
end
```

## Inspect The Runtime

List available workflows:

```bash
curl -sS http://127.0.0.1:4111/v1/workflows | jq
```

Run a workflow:

```bash
curl -sS -X POST http://127.0.0.1:4111/v1/workflows/hello/runs \
  -H 'content-type: application/json' \
  -d '{"input":{"content":"hello"}}' | jq
```

## Try The Playground

```bash
cd packages/playground
bun install
bun run dev
```

## Next Steps

- Read [Core Concepts](/guides/core-concepts)
- Learn the [.acd.cr workflow format](/guides/workflow-format)
- Review [registry extensions](/guides/registry)
- Browse [examples](/guides/examples)
