# Quickstart

Get started with Ocawe in minutes. Build your first Cawfile workflow with
agents, tools, and the Crystal-native runtime.

## Prerequisites

- Nix, or `curl`/`wget` for GitHub Releases installation
- Crystal (>= 1.9.0) only when building from source
- Node.js and pnpm only for playground and docs development

## Installation

Install with Nix:

```bash
nix profile install github:lefinepro/ocawe
ocawe --help
```

Or install from GitHub Releases:

```bash
curl -fsSL https://github.com/lefinepro/ocawe/releases/latest/download/install.sh | bash
export PATH="$HOME/.local/bin:$PATH"
ocawe --help
```

For source development:

```bash
git clone https://github.com/lefinepro/ocawe.git
cd ocawe
nix develop
crystal build src/cli/main.cr -o build/ocawe
```

## Start the Runtime

Start a packaged example workflow:

```bash
pkg="$(dirname "$(dirname "$(readlink -f "$(command -v ocawe)")")")"
tmp="$(mktemp -d)"
cp -R "$pkg/share/ocawe/caws/12-api-nodes" "$tmp/"
chmod -R u+w "$tmp/12-api-nodes"

ocawe up -d "$tmp/12-api-nodes" --port 4119
curl -fsS http://127.0.0.1:4119/v1/workflows
kill "$(cat "$tmp/12-api-nodes/.ocawe.pid")"
```

The runtime reads settings and workflows from the selected `Cawfile`. Packaged
examples are copied to a writable temporary directory because detached mode
writes `.ocawe.pid` next to the workflow.

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
