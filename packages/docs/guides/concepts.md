# Core Concepts

Understand the fundamental building blocks of Ocawe: workflows, agents, tools, and execution patterns.

## Overview

Ocawe is a Crystal-first Cawfile framework and runtime for building
AI-powered workflows. It provides:

- **Cawfile framework** - Define runtime settings, structs, services, and multiple workflows in one root file
- **Declarative workflow DSL** - Define complex agent pipelines in Crystal
- **Runtime execution engine** - Execute workflows with state management and control flow
- **HTTP APIs** - Trigger and manage workflows via REST endpoints
- **Dataset storage** - Back workflow state, queues, and task APIs with memory, file, or SQLite stores
- **MCP integration** - Connect external tools and resources
- **ACP execution** - Run external AI agents through the Agent Client Protocol
- **Type-safe schemas** - Validate inputs and outputs with Crystal types

## When to Use What

### Use Workflows When:

- You need deterministic, multi-step processes
- You want explicit control flow (parallel, conditional, loops)
- You need to chain multiple agents or tools together
- You require state management across steps
- You want suspend/resume capabilities

**Example use cases:**
- Document processing pipelines
- Multi-stage analysis workflows
- Approval workflows with human-in-the-loop
- Data transformation pipelines

### Use Agents When:

- You need natural language understanding
- You want LLM-powered decision making
- You need contextual responses
- You want to use tools dynamically
- You need memory/conversation history

**Example use cases:**
- Customer support chatbots
- Code review assistants
- Research and summarization
- Q&A systems

### Use Tools When:

- You need to extend agent capabilities
- You want to connect external services
- You need custom business logic
- You want to interact with APIs or databases

**Example use cases:**
- Database queries
- API integrations
- File operations
- Custom calculations

## Core Components

### Workflows

Workflows are declarative definitions of agent pipelines written in the Cawfile
DSL. A root `Cawfile` can contain settings and multiple workflows:

```crystal
settings do
  port = 4111
  datasets.adapter = "sqlite"
end

@[Service]
workflow "agent-tunnel" do
  exec "localtunnel", runtime: {shell: "bash"}
end

workflow "example" do
  agent "researcher"
  agent "analyzer"
  agent "reporter"
end
```

Directory-local `Cawfile` files are preferred for workflow bundles. `.acd.cr`
files remain supported as legacy or single-workflow fallback.

**Service workflows** use `@[Service]` and start when the runtime starts or
reloads. Use them for long-lived helpers such as tunnels, daemons, watchers,
or background schedulers.

**Key features:**
- Crystal-native DSL
- Type-safe execution
- Built-in control flow (parallel, conditional, loops)
- State management
- Suspend/resume support
- OpenAI-compatible workflow-as-model and async task execution

### Agents

Agents are LLM-powered nodes that process inputs and generate outputs. They're defined in markdown files with frontmatter configuration.

**Agent definition** (`agents/assistant.md`):

```markdown
---
description: "Helpful assistant"
model: "openai/gpt-4"
---

You are a helpful assistant. Answer questions concisely and accurately.
```

**Agent usage in workflow**:

```crystal
workflow "example" do
  agent "assistant",
    model: "openai/gpt-4",
    prompt: "Custom prompt override"
end
```

**Key features:**
- Model selection (OpenAI, Anthropic, local models)
- Schema validation (input/output/resume schemas)
- Guardrails (input filtering, output validation)
- Voice capabilities (STT/TTS)
- Memory and context management

### Tools

Tools extend agent capabilities by providing functions they can call.

**Built-in tool types:**
- **External scripts** - Shell scripts, Python, Ruby, etc.
- **MCP tools** - Model Context Protocol integrations
- **Internal functions** - Crystal NodeKind handlers

**External script tool**:

```crystal
workflow "example" do
  exec "tools/fetch_data.sh",
    runtime: {shell: "bash"},
    env: {API_KEY: "..."}
end
```

**ACP agent execution**:

```crystal
workflow "example" do
  exec "codex",
    runtime: {acp: {command: "codex", args: ["--server"]}}
end
```

**MCP tool**:

```crystal
workflow "example" do
  exec "mcp:fetch_data",
    runtime: nil  # MCP tools don't need runtime
end
```

**Internal function tool**:

```crystal
# Register in Crystal
Ocawe::RegistryApi.node_kind("custom_function") do |ctx, attributes|
  {
    "result" => JSON.parse("success".to_json)
  }
end

# Use in workflow
workflow "example" do
  custom_function message: "hello"
end
```

### Skills

Skills are reusable agent capabilities that can be composed into workflows.

```crystal
workflow "example" do
  skill "translator",
    agent_id: "assistant",
    language: "es"
end
```

### Voice & RAG

Special workflow nodes for voice and retrieval-augmented generation.

**Voice**:

```crystal
workflow "voice-example" do
  voice "speak",
    voice_operator: "openai",
    text: "Hello, world!"
end
```

**RAG**:

```crystal
workflow "rag-example" do
  rag "search",
    operation: "query",
    vectorStoreName: "docs",
    queryText: input.query,
    topK: 5
end
```

## Execution Model

### Workflow Lifecycle

1. **Parse** - Workflow DSL is parsed into execution graph
2. **Validate** - Schemas and configurations are validated
3. **Execute** - Nodes are executed in dependency order
4. **State** - State is managed across steps
5. **Output** - Final result is returned

### Node Input Envelope

Each node receives a standardized input envelope:

```json
{
  "input": "<previous-step-output>",
  "context": {
    "workflow_id": "example",
    "run_id": "run-123",
    "state": {...}
  }
}
```

### Control Flow

Ocawe supports rich control flow primitives:

**Parallel execution**:

```crystal
parallel do
  agent "analyzer-1"
  agent "analyzer-2"
end
```

**Conditional branching**:

```crystal
if input.type == "question"
  agent "qa-agent"
elsif input.type == "task"
  agent "task-agent"
else
  agent "general-agent"
end
```

**Loops**:

```crystal
# While loop
while state.needs_refinement do
  agent "refiner"
end

# Until loop
until state.quality_score > 0.9 do
  agent "improver"
end
```

### State Management

Workflows maintain state across steps:

```crystal
workflow "stateful-example" do
  agent "step-1"  # Output stored in state
  
  # Access previous step output via input
  agent "step-2"  # Receives step-1 output as input
  
  # State accessible in conditionals
  if state.step_1_result == "success"
    agent "step-3"
  end
end
```

### Suspend & Resume

Workflows can suspend for human approval or external input:

```crystal
workflow "approval-flow" do
  agent "analyzer"
  
  suspend "approval",
    reason: "Requires human review",
    resume_schema: schema_ref("approval")
  
  agent "executor"  # Runs after resume
end
```

Resume via API:

```bash
curl -X POST http://localhost:4111/v1/workflows/approval-flow/runs/run-123/resume \
  -H "Content-Type: application/json" \
  -d '{"approved": true, "feedback": "Looks good"}'
```

## Schema Validation

Type-safe schemas ensure data validity:

**Agent with schemas** (`agents/validator.md`):

````markdown
---
description: "Validator agent"
---

```crystal schema:input
Schema::Types.object({
  "query" => Schema::Types.of(String)
}, strict: true)
```

```crystal schema:output
Schema::Types.object({
  "response" => Schema::Types.of(String),
  "confidence" => Schema::Types.of(Float64)
}, strict: true)
```
````

**Workflow usage**:

```crystal
workflow "validated" do
  agent "validator",
    input_schema: schema_ref("input"),
    output_schema: schema_ref("output")
end
```

## Runtime APIs

### Trigger API

Canonical invocation layer:

```bash
# Workflow trigger
POST /v1/triggers/workflows/{id}

# Agent trigger
POST /v1/triggers/agents/{id}

# Skill trigger
POST /v1/triggers/skills/{id}

# Function trigger
POST /v1/triggers/functions/{id}
```

### Workflow Management API

```bash
# List workflows
GET /v1/workflows

# Create run
POST /v1/workflows/{workflowId}/runs

# Resume run
POST /v1/workflows/{workflowId}/runs/{runId}/resume
```

### MCP API

Manage Model Context Protocol servers:

```bash
# List MCP servers
GET /v1/mcp/servers

# Get MCP catalog (tools, resources, prompts)
GET /v1/mcp/catalog
```

## Next Steps

- **[Quickstart](/guides/quickstart)** - Build your first workflow
- **[Agents Guide](/guides/agents)** - Deep dive into agents
- **[Workflows Guide](/guides/workflows)** - Master workflow patterns
- **[Tools Guide](/guides/tools)** - Create custom tools
- **[API Reference](/api/reference)** - Complete API docs
