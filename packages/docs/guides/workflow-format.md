# Workflow Format (`Cawfile` and `.acd.cr`)

Ocawe workflows use a Crystal-like Cawfile DSL. The preferred format is a root
or bundle-local `Cawfile`; `.acd.cr` files remain supported for legacy and
single-workflow layouts.

Root `Cawfile` example:

```crystal
settings do
  port = 4111
  datasets.adapter = "sqlite"
  telemetry do
    enabled = true
    service_name = "ocawe"
    endpoint = "http://127.0.0.1:4318"
  end
end

@[Service]
workflow "agent-tunnel" do
  exec "localtunnel", runtime: {shell: "bash"}
end

workflow "agents-example" do
  agent "simple-agent", model: "openai/gpt-4.1-mini"
end
```

A root `Cawfile` can define runtime settings, Crystal structs, annotations, and
multiple `workflow` blocks. A bundle-local `Cawfile` is loaded before legacy
`<id>.acd.cr` files.

## OpenTelemetry

Enable OTEL from `settings do` or standard `OTEL_*` environment variables:

```crystal
settings do
  telemetry do
    enabled = true
    service_name = "ocawe-runtime"
    endpoint = "http://127.0.0.1:4318"
    tracesEnabled = true
    metricsEnabled = true
    logsEnabled = true
  end
end
```

Ocawe emits HTTP server spans, workflow run spans, node spans, outbound API/exec spans, workflow metrics, HTTP metrics, and OTEL log records mirrored from workflow logger events. `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_HEADERS`, `OTEL_SERVICE_NAME`, and signal-specific exporter env vars override file settings.

## Agent Configuration

Set model and schema options per-agent directly on each `agent` node:

```crystal
workflow "example" do
  agent "my-agent",
    model: "openai/gpt-4.1",
    prompt: "Your agent prompt"
end
```

### `@[Logger(...)]` Annotation

`@[Logger(...)]` supports Mastra-compatible logger config keys:
- `name` (string)
- `level` (`trace|debug|info|warn|error|fatal`)
- `transports` (array of objects)
- `overrideDefaultTransports` (boolean)
- `formatters` (object)

```crystal
workflow "logger-example" do
  # Workflow-level logger default
  @[Logger(name: "ocawe", level: "info")]

  # Node-level override (applies to the next node only)
  @[Logger(level: "debug")]
  agent "analyzer"

  my_tool
end
```

Parser is strict: unknown keys or invalid types raise workflow parse errors.
Runtime currently supports console output transport; non-console transports are preserved in metadata and ignored at execution time.

### `@[Workspace(...)]` Annotation

`@[Workspace(...)]` configures workspace metadata for runtime nodes.

- If used before the first node, it becomes workflow default workspace.
- If used after nodes have started, it applies to the next node only.
- Optional `scope: "workflow" | "node" | "next"` can force scope.
- Custom keys are allowed and passed through; extension logic can validate/resolve via `Ocawe::RegistryApi.workspace_*`.

```crystal
workflow "workspace-flow" do
  @[Workspace(provider: "docker", repo: "org/repo", scope: "workflow")]
  exec "prepare", runtime: {shell: "bash"}

  @[Workspace(branch: "main")]
  exec "build", runtime: {shell: "bash"}
end
```

### `container do` Block

`container do` declares how the Cawfile bundle is packaged into a container image
when you run `ocawe build` / `ocawe up`. The same container config applies to
every workflow in the Cawfile, including `@[Service]` workflows.

If the command is launched with an existing `CODEX_HOME`, Ocawe mounts only
its `auth.json` read-only and gives Codex a writable tmpfs home inside the
container. This lets a `codex-acp` package authenticate without copying
credentials into the image, sharing a host model cache, or writing host paths
into the Cawfile.

| Field | Type | Description |
|-------|------|-------------|
| `packages` | `String[]` | Nix package names plus flake/path refs such as `github:owner/tool` or `./local-tool`. |
| `files` | `String[]` | Optional files/directories copied into the build context. Omit to copy bundle entries at build time, excluding ignored build/cache directories. |

```crystal
container do
  packages = ["git", "curl", "jq", "github:owner/tool"]
  files = ["agents", "skills", "tools"]
end

workflow "container-workflow" do
  agent "analyzer"
end
```

> **Legacy-compatible:** `@[Container(...)]` is still parsed, but new Cawfiles
> should use the root `container do` block.

### `@[Service]` Annotation

`@[Service]` marks a workflow as a runtime service. Service workflows are
discovered from the active `Cawfile` and started by `ocawe up` when the HTTP
runtime boots or reloads.

Use service workflows for long-lived helpers such as local tunnels, watchers,
sidecar agents, or schedulers:

```crystal
@[Service]
workflow "agent-tunnel" do
  exec "localtunnel", runtime: {shell: "bash"}
end
```

Service state is tracked separately from normal workflow triggers. When a
service exits or fails, the runtime clears its started marker so a later reload
can start it again.

## Execution Control

### Parallel Execution

Execute multiple agents concurrently using `parallel do...end`:

```crystal
workflow "parallel-workflow" do

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

  while state.needs_refinement do
    agent "refiner"
  end
end
```

### Until Loop

Use `until condition do...end` to repeat execution until condition becomes true:

```crystal
workflow "until-workflow" do

  until state.quality_score > 0.9 do
    agent "improver"
  end
end
```

## Directives Reference

### Core Directives

| Directive | Description |
|-----------|-------------|
| `@[Logger(...)]` | Configure workflow/node logging metadata and runtime log level/shape |
| `@[Workspace(...)]` | Configure workflow-level or next-node workspace metadata |
| `container do` | Configure bundle-level container packaging (`packages`, optional `files`) for `ocawe build`/`up` |
| `@[Service]` | Start workflow automatically with the runtime |
| `agent "..."` | Define agent node |
| `skill "..."` | Define skill node |
| `function_name` | Execute internal node kind (registered via `NodeKind::new(function_name)`) |
| `exec "path_or_inline", runtime: {...}, env: {...}` | Execute external script path, inline script, MCP tool, or ACP agent |
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

For `agent`, `exec`, and internal function-name nodes, runtime passes a chained input envelope:

```json
{"input": <previous step output>, "context": {"workflow_id": "...", "run_id": "...", "state": {...}}}
```

If exec/internal-node attributes are defined in DSL, runtime includes these attributes as flat fields in the input envelope.

For internal function-name nodes, `input_schema` and `output_schema` are reserved schema keys; all other named args are passed through as node attributes.

## ACP Runtime

`exec` can run an external Agent Client Protocol process by passing an `acp`
runtime block:

```crystal
workflow "codex-acp" do
  exec "codex",
    runtime: {
      acp: {
        command: "codex",
        args: ["--server"],
        env: {CODEX_HOME: ".codex"}
      }
    }
end
```

The runtime starts the process over stdio, opens an ACP session, sends the
node input as the prompt, and returns structured ACP output to the workflow.

## Function Resolution and Aliases

`function_name` resolves node-kind handlers by normalized case-insensitive key.

- If a system and user function share the same name, system keeps base name.
- User collisions are indexed as `name:1`, `name:2`, ...
- You can add explicit aliases during registration and call them via `alias` node invocation syntax.

Register runtime extensions through `Ocawe::RegistryApi`:
- `Ocawe::RegistryApi.node_kind`
- `Ocawe::RegistryApi.resource`

## Examples

### Basic Workflow

```crystal
workflow "basic" do
  agent "assistant"
end
```

### Multi-Agent Pipeline

```crystal
workflow "pipeline" do

  agent "researcher"
  agent "analyzer"
  agent "reporter"
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

  agent "synthesizer"
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

## Full Coverage Example

See `shards/examples/full-capabilities/full-capabilities.acd.cr`.

## Programmatic Control-Flow

`parallel`, `then`, `wait_for_event`, and `send_event` remain available via programmatic workflow DSL in
`shards/examples/src/control_flow_workflow_example.cr`.
