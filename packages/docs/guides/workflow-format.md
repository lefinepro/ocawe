# Workflow Format (`.acd.cr`)

Cogni workflows use Crystal DSL files with extension `.acd.cr`.

Example:

```crystal
workflow "agents-example" do
  @[Resources(model: "cliproxyapi/qwen3-coder-plus")]
  agent "simple-agent"
end
```

## Resource Management

### `@[Resources(...)]` Annotation

The `@[Resources(...)]` annotation provides a unified way to declare models, skills, and tools:

```crystal
workflow "example" do
  # Single model
  @[Resources(model: "openai/gpt-4.1")]

  # Single skill
  @[Resources(skill: "translation")]

  # Multiple skills (array syntax)
  @[Resources(skill: ["translation", "summarization"])]

  # Multiple tools
  @[Resources(tool: ["http-client", "file-reader"])]

  # Combined declaration
  @[Resources(model: "openai/gpt-4.1", skill: ["translation", "summarization"], tool: ["http-client"])]

  agent "my-agent"
end
```

## Execution Control

### Parallel Execution

Execute multiple agents concurrently using `parallel do...end`:

```crystal
workflow "parallel-workflow" do
  @[Resources(model: "openai/gpt-4.1")]

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
  @[Resources(model: "openai/gpt-4.1")]

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
  @[Resources(model: "openai/gpt-4.1")]

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
  @[Resources(model: "openai/gpt-4.1")]

  while state.needs_refinement do
    agent "refiner"
  end
end
```

### Until Loop

Use `until condition do...end` to repeat execution until condition becomes true:

```crystal
workflow "until-workflow" do
  @[Resources(model: "openai/gpt-4.1")]

  until state.quality_score > 0.9 do
    agent "improver"
  end
end
```

## Directives Reference

### Core Directives

| Directive | Description |
|-----------|-------------|
| `@[Resources(model: "...")]` | Set default model for workflow |
| `@[Resources(skill: "...")]` or `@[Resources(skill: [...])]` | Declare skills |
| `@[Resources(tool: "...")]` or `@[Resources(tool: [...])]` | Declare tools |
| `agent "..."` | Define agent node |
| `skill "..."` | Define skill node |
| `run "name"` | Execute registered function |
| `run "path_or_inline", runtime: {...}, env: {...}` | Execute script path or inline script |
| `voice "..."` | Voice node |
| `rag "..."` | RAG node |
| `suspend "..."` | Suspend-and-resume node (`reason`, `resume_schema`) |

### Agent Options

```crystal
agent "my-agent",
  model: "openai/gpt-4.1",
  prompt: "Custom system prompt",
  input_schema: schema_ref("input"),
  output_schema: schema_ref("output"),
  resume_schema: schema_ref("resume")
```

### Control Flow

| Block | Description |
|-------|-------------|
| `parallel do...end` | Execute contained agents concurrently |
| `if...elsif...else...end` | Conditional branching |
| `unless...else...end` | Inverted conditional (execute when false) |
| `while condition do...end` | Loop while condition is true |
| `until condition do...end` | Loop until condition becomes true |
| `loop do...end` | Loop until node flow suspends/fails or max iterations reached |

## Agent Schema References

```crystal
agent "workflow-agent",
  input_schema: schema_ref("input"),
  output_schema: schema_ref("output"),
  resume_schema: schema_ref("resume")
```

`schema_ref("input")` / `schema_ref("output")` / `schema_ref("resume")` resolve markdown `crystal` schema blocks from the agent file.

For `agent` and `run` function nodes, runtime passes a chained input envelope:

```json
{"input": <previous step output>, "context": {"workflow_id": "...", "run_id": "...", "state": {...}}}
```

If run params are defined in DSL, runtime includes these params as flat fields in the run input envelope.

## Function Resolution and Aliases

`run "name"` resolves functions by normalized case-insensitive key.

- If a system and user function share the same name, system keeps base name.
- User collisions are indexed as `name:1`, `name:2`, ...
- You can add explicit aliases during registration and call them directly via `run "alias"`.

Register runtime extensions through `Cogni::Registry`:
- `Cogni::Registry.node_kind`
- `Cogni::Registry.resource`

## Examples

### Basic Workflow

```crystal
workflow "basic" do
  @[Resources(model: "openai/gpt-4.1")]
  agent "assistant"
end
```

### Multi-Agent Pipeline

```crystal
workflow "pipeline" do
  @[Resources(model: "openai/gpt-4.1")]

  agent "researcher"
  agent "analyzer"
  agent "reporter"
end
```

### Parallel Processing

```crystal
workflow "parallel-analysis" do
  @[Resources(model: "openai/gpt-4.1")]

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
  @[Resources(model: "openai/gpt-4.1")]

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

`parallel`, `then`, `wait_for_event`, and `send_event` remain available via programmatic workflow DSL in
`shards/examples/src/control_flow_workflow_example.cr`.
