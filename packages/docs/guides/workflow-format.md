# Workflow Format (`.acd.cr`)

Cogni workflows use Crystal DSL files with extension `.acd.cr`.

Example:

```crystal
workflow "agents-example" do
  use model: "cliproxyapi/qwen3-coder-plus"
  agent "simple-agent"
end
```

## Resource Management

### Unified `use` Attribute

The `use` attribute provides a unified way to declare models, skills, and tools:

```crystal
workflow "example" do
  # Single model
  use model: "openai/gpt-4.1"

  # Single skill
  use skill: "translation"

  # Multiple skills (array syntax)
  use skill: ["translation", "summarization"]

  # Multiple tools
  use tool: ["http-client", "file-reader"]

  # Combined declaration
  use model: "openai/gpt-4.1",
      skill: ["translation", "summarization"],
      tool: ["http-client"]

  agent "my-agent"
end
```

## Execution Control

### Parallel Execution

Execute multiple agents concurrently using `parallel do...end`:

```crystal
workflow "parallel-workflow" do
  use model: "openai/gpt-4.1"

  parallel do
    agent "analyzer-1"
    agent "analyzer-2"
    agent "analyzer-3"
  end
end
```

All agents inside the `parallel` block run concurrently, and their results are merged.

### Conditional Execution

Use Crystal-native `if/elsif/else` for conditional branching:

```crystal
workflow "conditional-workflow" do
  use model: "openai/gpt-4.1"

  if input.task == "translate"
    agent "translator-agent"
  elsif input.task == "summarize"
    agent "summarizer-agent"
  else
    agent "general-agent"
  end
end
```

Conditions can reference:
- `input.<field>` - input data fields
- Any Crystal expression that evaluates to a boolean

### Unless Conditional

Use `unless` for inverted conditional logic (execute when condition is false):

```crystal
workflow "unless-workflow" do
  use model: "openai/gpt-4.1"

  unless input.language == "en"
    agent "translator"
  else
    agent "passthrough"
  end
end
```

### While Loop

Use `while condition do...end` to repeat execution while condition is true:

```crystal
workflow "while-workflow" do
  use model: "openai/gpt-4.1"

  while state.needs_refinement do
    agent "refiner"
  end
end
```

### Until Loop

Use `until condition do...end` to repeat execution until condition becomes true:

```crystal
workflow "until-workflow" do
  use model: "openai/gpt-4.1"

  until state.quality_score > 0.9 do
    agent "improver"
  end
end
```

## Directives Reference

### Core Directives

| Directive | Description |
|-----------|-------------|
| `use model: "..."` | Set default model for workflow |
| `use skill: "..."` or `use skill: [...]` | Declare skills |
| `use tool: "..."` or `use tool: [...]` | Declare tools |
| `agent "..."` | Define agent node |
| `skill "..."` | Define skill node |
| `tool snake_case` | Crystal tool function |
| `tool "path", runtime: {...}` | External tool |
| `voice "..."` | Voice node |
| `rag "..."` | RAG node |
| `approve "..."` | Human approval node |

### Agent Options

```crystal
agent "my-agent",
  model: "openai/gpt-4.1",
  prompt: "Custom system prompt",
  input_schema: schema_ref("input"),
  output_schema: schema_ref("output")
```

### Control Flow

| Block | Description |
|-------|-------------|
| `parallel do...end` | Execute contained agents concurrently |
| `if...elsif...else...end` | Conditional branching |
| `unless...else...end` | Inverted conditional (execute when false) |
| `while condition do...end` | Loop while condition is true |
| `until condition do...end` | Loop until condition becomes true |

## Agent Schema References

```crystal
agent "workflow-agent", input_schema: schema_ref("input"), output_schema: schema_ref("output")
```

`schema_ref("input")` / `schema_ref("output")` resolve markdown `crystal` schema blocks from the agent file.

For `agent` and bare `snake_case` function nodes, runtime passes a chained input envelope:

```json
{"input": <previous step output>, "context": {"workflow_id": "...", "run_id": "...", "state": {...}}}
```

If function params are defined in DSL, runtime includes these params as flat fields in the function input envelope.

## Examples

### Basic Workflow

```crystal
workflow "basic" do
  use model: "openai/gpt-4.1"
  agent "assistant"
end
```

### Multi-Agent Pipeline

```crystal
workflow "pipeline" do
  use model: "openai/gpt-4.1"

  agent "researcher"
  agent "analyzer"
  agent "reporter"
end
```

### Parallel Processing

```crystal
workflow "parallel-analysis" do
  use model: "openai/gpt-4.1"

  parallel do
    agent "sentiment-analyzer"
    agent "topic-extractor"
    agent "entity-recognizer"
  end

  agent "synthesizer"
end
```

### Conditional Routing

```crystal
workflow "smart-router" do
  use model: "openai/gpt-4.1"

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

## Full Coverage Example

See `shards/examples/full-capabilities/full-capabilities.acd.cr`.

## Programmatic Control-Flow

Methods like `branch`, `parallel`, `dowhile`, `dountil`, `while_loop`, `until_loop`, `unless_branch`,
`wait_for_event`, and `send_event` are also available via programmatic workflow DSL in
`shards/examples/src/control_flow_workflow_example.cr`.
