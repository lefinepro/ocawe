# Quickstart

Get started with Ocawe in minutes. Build your first AI workflow with agents, tools, and Crystal-native runtime.

## Prerequisites

- Crystal (>= 1.9.0)
- Bun or Node.js (for playground)

## Installation

Clone the repository and build the runtime:

```bash
git clone https://github.com/your-org/ocawe.git
cd ocawe
crystal build src/cli/main.cr -o build/ocawe
```

## Start the Runtime

Start the Ocawe runtime server:

```bash
./build/ocawe up --port 4111
```

The runtime is now listening on `http://localhost:4111`.

## Start the Playground (Optional)

For interactive development, start the Svelte playground:

```bash
cd packages/playground
bun install
bun run dev
```

Open your browser:
- Playground: `http://localhost:5173/playground/`
- Docs: `http://localhost:5173/`

## Your First Workflow

Create your first workflow file `hello-world.acd.cr`:

```crystal
workflow "hello-world" do
  agent "greeter",
    model: "openai/gpt-4",
    prompt: "You are a friendly assistant. Greet the user warmly."
end
```

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

## What's Next?

- **[Concepts](/guides/concepts)** - Understand agents, workflows, and tools
- **[Tutorial](/guides/tutorial)** - Build a complete workflow step-by-step
- **[Workflow Format](/guides/workflow-format)** - Learn the workflow DSL
- **[Examples](/guides/examples)** - Explore working examples
- **[API Reference](/api/reference)** - Complete API documentation

## Common Patterns

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
