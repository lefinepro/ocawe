# Ocawe

Build AI agents and workflows your users actually depend on. Ocawe is a Crystal-first runtime that gives you everything you need to prototype fast and ship with confidence.

## Quickstart

Build and start the runtime:

```bash
crystal build src/cli/main.cr -o build/ocawe
./build/ocawe up --port 4111
```

Create your first workflow (`hello-world.acd.cr`):

```crystal
workflow "hello-world" do
  agent "greeter",
    model: "openai/gpt-4",
    prompt: "You are a friendly assistant"
end
```

Run it:

```bash
./build/ocawe workflow hello-world input='{"message": "Hello!"}'
```

See the [quickstart guide](/guides/quickstart) for a full walkthrough.

## What You Can Build

**Customer-facing assistants** - Build agents that handle inquiries, schedule appointments, and answer questions via chat or voice.

**Internal copilots** - Help employees work faster with AI that understands your domain—HR queries, documentation, or data analysis.

**Data analysis workflows** - Let users query databases and documents in natural language. Return answers, charts, or reports.

**Content automation** - Generate, transform, and manage structured content at scale—for CMS, knowledge bases, or documentation systems.

**DevOps automation** - Automate deployments, debug production issues, manage infrastructure, and handle on-call workflows.

## Core Features

- **Declarative workflow DSL** - Crystal-native syntax for building complex agent pipelines
- **Type-safe execution** - Crystal's type system catches errors at compile time
- **Control flow primitives** - Parallel, conditional, loops, suspend/resume
- **Agent Client Protocol (ACP)** - Integrate external AI agents (Codex, Claude) via standardized protocol
- **Workflow-as-Model** - Execute workflows through OpenAI-compatible `/v1/chat/completions` API
- **MCP integration** - Connect external tools and resources via Model Context Protocol
- **HTTP APIs** - Trigger and manage workflows via REST endpoints
- **Dynamic model discovery** - `/v1/models` endpoint exposes workflows, agents, skills, and tools
- **Interactive playground** - Visual workflow builder and testing environment
- **Schema validation** - Type-safe input/output validation
- **Voice & RAG support** - Built-in voice and retrieval-augmented generation
- **ActivityPub federation** - Connect with remote agents and federated systems

## Getting Started

- **[Quickstart](/guides/quickstart)** - Get up and running in minutes
- **[Core Concepts](/guides/concepts)** - Understand agents, workflows, and tools
- **[Tutorial](/guides/tutorial)** - Build a complete workflow step-by-step
- **[Examples](/guides/examples)** - Explore working code samples

## Learn More

- **[Agents Guide](/guides/agents)** - Build intelligent agents with LLM capabilities
- **[Workflows Guide](/guides/workflows)** - Master workflow orchestration
- **[Tools Guide](/guides/tools)** - Extend capabilities with custom tools
- **[API Reference](/api/reference)** - Complete API documentation

## Playground

Start the interactive Svelte playground:

```bash
cd packages/playground
bun install
bun run dev
```

Open in your browser:
- Playground: `http://localhost:5173/playground/`
- Docs: `http://localhost:5173/`

## License

Dual-licensed under [ISC](https://spdx.org/licenses/ISC.html) (`LICENSE`) and [0BSD](https://spdx.org/licenses/0BSD.html) (`LICENSE-0BSD`).
