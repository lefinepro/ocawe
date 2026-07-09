# Quickstart

Get started with Ocawe in minutes. Build your first Cawfile workflow with
agents, tools, and the Crystal-native runtime.

## Prerequisites

- Crystal (>= 1.9.0)
- Node.js and pnpm (for playground and docs)

## Installation

Clone the repository and build the runtime:

```bash
git clone https://github.com/lefinepro/ocawe.git
cd ocawe
crystal build src/cli/main.cr -o build/ocawe
```

## Start the Runtime

Start the Ocawe runtime server:

```bash
./build/ocawe up
```

The runtime reads settings and workflows from the root `Cawfile`. With the
example below, it listens on `http://localhost:4111`.

## Start the Playground (Optional)

For interactive development, start the Svelte playground:

```bash
cd packages/playground
pnpm install
pnpm run dev
```

Open your browser:
- Playground: `http://localhost:5173/playground/`
- Docs: `http://localhost:5173/`

## Your First Workflow

Create a root `Cawfile`:

```crystal
settings do
  port = 4111
  datasets.adapter = "sqlite"
end

workflow "hello-world" do
  agent "greeter",
    model: "openai/gpt-4",
    prompt: "You are a friendly assistant. Greet the user warmly."
end
```

A root `Cawfile` can hold multiple workflows. Directory-local `Cawfile` files
are preferred for bundles, and `.acd.cr` files remain supported for legacy or
single-workflow layouts.

## Run Your Workflow

Execute your workflow via the Trigger API:

```bash
./build/ocawe workflow hello-world input='{"message": "Hello!"}'
```

Or via HTTP:

```bash
curl -X POST http://localhost:4111/v1/triggers/workflows/hello-world \
  -H "Content-Type: application/json" \
  -d '{"input": {"message": "Hello!"}}'
```

Or through the OpenAI-compatible workflow-as-model API:

```bash
curl -X POST http://localhost:4111/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "workflow/hello-world",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

For queued work, use `POST /v1/chat/completions/tasks` and poll the returned
`status_url`.

## What's Next?

- **[Concepts](/guides/concepts)** - Understand agents, workflows, and tools
- **[Tutorial](/guides/tutorial)** - Build a complete workflow step-by-step
- **[Workflow Format](/guides/workflow-format)** - Learn the workflow DSL
- **[Examples](/guides/examples)** - Explore working examples
- **[API Reference](/api/reference)** - Complete API documentation

## Common Patterns

### Service Workflow

```crystal
@[Service]
workflow "agent-tunnel" do
  exec "localtunnel", runtime: {shell: "bash"}
end
```

### External ACP Agent

```crystal
workflow "codex-acp" do
  exec "codex",
    runtime: {acp: {command: "codex", args: ["--server"]}}
end
```

### Multi-Agent Pipeline

```crystal
workflow "research-pipeline" do
  agent "researcher",
    prompt: "Research the given topic thoroughly"
  
  agent "analyzer",
    prompt: "Analyze the research findings"
  
  agent "reporter",
    prompt: "Generate a comprehensive report"
end
```

### Parallel Processing

```crystal
workflow "parallel-analysis" do
  parallel do
    agent "sentiment-analyzer"
    agent "topic-extractor"
    agent "entity-recognizer"
  end
  
  agent "synthesizer",
    prompt: "Synthesize all analysis results"
end
```

### Conditional Routing

```crystal
workflow "smart-router" do
  if input.language != "en"
    agent "translator"
  end
  
  if input.type == "question"
    agent "qa-agent"
  elsif input.type == "task"
    agent "task-agent"
  else
    agent "general-agent"
  end
end
```

## Need Help?

- Check the [Tutorial](/guides/tutorial) for a comprehensive walkthrough
- Browse [Examples](/guides/examples) for working code
- Explore the [API Reference](/api/reference) for detailed specs
