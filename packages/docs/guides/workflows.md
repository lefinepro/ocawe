# Workflows Guide

Master workflow orchestration with control flow, state management, and advanced patterns. Build complex multi-agent systems with deterministic execution.

## What are Workflows?

Workflows are declarative definitions of agent pipelines written in Crystal DSL (`.acd.cr` files). They provide:

- **Deterministic execution** - Predictable, reproducible behavior
- **Control flow** - Parallel, conditional, loops
- **State management** - Share data across steps
- **Type safety** - Crystal's type system catches errors early
- **Suspend/resume** - Human-in-the-loop patterns

## When to Use Workflows

**Use workflows when:**
- You need multi-step processes
- You want explicit control flow
- You need to chain agents and tools
- You require state management
- You want suspend/resume capabilities
- You need reproducible, testable logic

**Use standalone agents when:**
- Single-purpose, one-shot interactions
- Simple request/response patterns
- No state management needed

## Creating Workflows

### Basic Workflow

Create a workflow file `workflows/example.acd.cr`:

```crystal
workflow "example" do
  agent "assistant",
    prompt: "You are a helpful assistant"
end
```

### Multi-Step Workflow

Chain multiple steps together:

```crystal
workflow "pipeline" do
  # Step 1: Research
  agent "researcher",
    prompt: "Research the given topic"
  
  # Step 2: Analyze (receives researcher output)
  agent "analyzer",
    prompt: "Analyze the research findings"
  
  # Step 3: Report (receives analyzer output)
  agent "reporter",
    prompt: "Generate a comprehensive report"
end
```

Each step automatically receives the previous step's output as `input`.

### Running Workflows

**Via Trigger API**:

```bash
curl -X POST http://localhost:4111/v1/triggers/workflows/example \
  -H "Content-Type: application/json" \
  -d '{"input": {"topic": "Crystal programming"}}'
```

**Via CLI**:

```bash
./build/ocawe workflow example topic="Crystal programming"
```

**Via Workflow API**:

```bash
curl -X POST http://localhost:4111/v1/workflows/example/runs \
  -H "Content-Type: application/json" \
  -d '{"input": {"topic": "Crystal programming"}}'
```

## Control Flow

### Parallel Execution

Execute multiple steps concurrently:

```crystal
workflow "parallel-analysis" do
  # All three agents run in parallel
  parallel do
    agent "sentiment-analyzer"
    agent "topic-extractor"
    agent "entity-recognizer"
  end
  
  # Synthesizer receives merged results from all parallel agents
  agent "synthesizer",
    prompt: "Combine all analysis results"
end
```

**Performance benefit**: 3x faster than sequential execution.

### Conditional Branching

Use Crystal's `if/elsif/else` for conditional logic:

```crystal
workflow "smart-router" do
  # Translate non-English input
  if input.language != "en"
    agent "translator"
  end
  
  # Route based on input type
  if input.type == "question"
    agent "qa-agent"
  elsif input.type == "task"
    agent "task-agent"
  elsif input.type == "analysis"
    agent "analysis-agent"
  else
    agent "general-agent"
  end
end
```

**Access state in conditionals**:

```crystal
workflow "state-conditional" do
  agent "analyzer"
  
  # Check previous step output
  if state.analyzer_confidence > 0.9
    agent "executor"
  else
    agent "human-reviewer"
  end
end
```

### Unless Conditional

Inverted conditional logic:

```crystal
workflow "unless-example" do
  unless input.skip_validation
    agent "validator"
  end
  
  agent "processor"
end
```

### While Loop

Repeat while condition is true:

```crystal
workflow "iterative-improvement" do
  agent "draft-generator"
  
  while state.quality_score < 0.9 do
    agent "critic"
    agent "refiner"
  end
  
  agent "finalizer"
end
```

**Max iterations**: Default 100 (prevents infinite loops).

### Until Loop

Repeat until condition becomes true:

```crystal
workflow "until-example" do
  agent "processor"
  
  until state.completed do
    agent "checker"
    agent "refinement"
  end
end
```

### Loop (Unbounded)

Loop until explicit break or max iterations:

```crystal
workflow "continuous-processing" do
  loop do
    agent "task-fetcher"
    agent "task-processor"
    
    # Break on specific condition
    if state.no_more_tasks
      break
    end
  end
end
```

## State Management

### Accessing Previous Outputs

Each step receives previous output as `input`:

```crystal
workflow "data-pipeline" do
  exec "fetch_data.sh",
    runtime: {shell: "bash"}
  # Output: {"data": [...]}
  
  agent "processor"
  # Receives: input = {"data": [...]}
  # Prompt can reference: "Process this data: #{input.data}"
end
```

### Workflow State

Access any previous step's output via `state`:

```crystal
workflow "complex-state" do
  agent "step1"
  agent "step2"
  agent "step3"
  
  # Access specific step outputs
  if state.step1_result == "success"
    agent "success-handler"
  end
  
  # Combine multiple step outputs
  agent "synthesizer",
    prompt: "Synthesize results from step1 and step2"
end
```

### State Schema

Define and validate workflow state:

```crystal
workflow "stateful" do
  @[StateSchema({
    "status" => Schema::Types.of(String),
    "count" => Schema::Types.of(Int32)
  })]
  
  agent "processor"
end
```

### Resource State

Pass resources through workflow:

```bash
curl -X POST http://localhost:4111/v1/workflows/example/runs \
  -H "Content-Type: application/json" \
  -d '{
    "input": {"query": "test"},
    "resources": {
      "database_url": "postgres://...",
      "api_key": "secret"
    }
  }'
```

Access in workflow:

```crystal
workflow "resource-access" do
  exec "query_db.sh",
    runtime: {shell: "bash"},
    env: {
      DATABASE_URL: state.resources.database_url
    }
end
```

## Suspend & Resume

### Basic Suspension

Pause workflow for external input:

```crystal
workflow "approval-flow" do
  agent "analyzer"
  
  suspend "approval",
    reason: "Requires human review"
  
  agent "executor"
end
```

**Resume workflow**:

```bash
curl -X POST http://localhost:4111/v1/workflows/approval-flow/runs/{runId}/resume \
  -H "Content-Type: application/json" \
  -d '{"approved": true}'
```

### Suspension with Schema

Validate resume data:

````markdown
# agents/analyzer.md

```crystal schema:resume
Schema::Types.object({
  "approved" => Schema::Types.of(Bool),
  "feedback" => Schema::Types.of(String, optional: true),
  "changes_required" => Schema::Types.array(Schema::Types.of(String))
}, strict: true)
```
````

```crystal
workflow "validated-approval" do
  agent "analyzer"
  
  suspend "approval",
    reason: "Review required",
    resume_schema: schema_ref("resume")
  
  # Resume data validated before execution continues
  if state.approval_data.approved
    agent "executor"
  else
    agent "reviser"
  end
end
```

### Multi-Stage Suspension

```crystal
workflow "multi-approval" do
  agent "draft-generator"
  
  suspend "technical-review",
    reason: "Technical approval needed"
  
  agent "technical-refinement"
  
  suspend "business-review",
    reason: "Business approval needed"
  
  agent "finalizer"
end
```

## Advanced Patterns

### Map Over Collection

Process multiple items:

```crystal
workflow "batch-processor" do
  # Fetch items
  exec "fetch_items.sh",
    runtime: {shell: "bash"}
  # Output: {"items": [item1, item2, item3]}
  
  # Process each item
  foreach do
    agent "item-processor"
  end
  
  # Aggregate results
  agent "aggregator"
end
```

### Event-Driven Workflows

```crystal
workflow "event-driven" do
  send_event "processing_started",
    data: {workflow_id: context.workflow_id}
  
  agent "processor"
  
  wait_for_event "external_validation",
    timeout: 3600  # 1 hour
  
  agent "finalizer"
end
```

### Timeout Handling

```crystal
workflow "with-timeout" do
  agent "long-running-task"
  
  sleep 30  # Wait 30 seconds
  
  if !state.task_completed
    agent "timeout-handler"
  end
end
```

### Error Recovery

```crystal
workflow "resilient" do
  agent "primary-processor"
  
  if state.primary_failed
    agent "fallback-processor"
    
    if state.fallback_failed
      agent "error-reporter"
      suspend "manual-intervention"
    end
  end
end
```

### Nested Workflows

```crystal
# Parent workflow
workflow "parent" do
  agent "preprocessor"
  
  # Call child workflow
  workflow_call "child-workflow",
    input: state.preprocessor_output
  
  agent "postprocessor"
end

# Child workflow (defined separately)
workflow "child-workflow" do
  agent "specialized-task"
end
```

### Dynamic Branching

```crystal
workflow "dynamic-router" do
  agent "router",
    prompt: "Analyze input and decide routing strategy"
  # Output: {"route": "technical", "priority": "high"}
  
  case state.router_output.route
  when "technical"
    agent "technical-specialist"
  when "business"
    agent "business-specialist"
  when "legal"
    agent "legal-specialist"
  else
    agent "general-handler"
  end
end
```

## Workflow Annotations

### Logger Configuration

Configure logging per workflow or node:

```crystal
workflow "logged-workflow" do
  # Workflow-level logger
  @[Logger(name: "ocawe", level: "info")]
  
  agent "step1"
  
  # Node-level logger override
  @[Logger(level: "debug")]
  agent "debug-step"
  
  agent "step3"
end
```

**Logger options**:
- `name` - Logger name (string)
- `level` - Log level (`trace`, `debug`, `info`, `warn`, `error`, `fatal`)
- `transports` - Output destinations (array)
- `formatters` - Custom formatting (object)

### Workspace Configuration

Configure workspace metadata:

```crystal
workflow "workspace-flow" do
  # Workflow-level workspace
  @[Workspace(provider: "docker", repo: "org/repo")]
  
  exec "build.sh",
    runtime: {shell: "bash"}
  
  # Node-level workspace override
  @[Workspace(branch: "main")]
  exec "deploy.sh",
    runtime: {shell: "bash"}
end
```

## External Script Execution

### Shell Scripts

```crystal
workflow "shell-execution" do
  exec "tools/fetch_data.sh",
    runtime: {shell: "bash"},
    env: {
      API_KEY: "secret",
      BASE_URL: "https://api.example.com"
    }
end
```

### Inline Scripts

```crystal
workflow "inline-script" do
  exec """
    #!/bin/bash
    echo '{"result": "success"}'
  """,
    runtime: {shell: "bash"}
end
```

### Python Scripts

```crystal
workflow "python-execution" do
  exec "tools/analyze.py",
    runtime: {
      command: "python3",
      args: ["--input", input.data_path]
    }
end
```

### Script Output

Scripts must output JSON to stdout:

```bash
#!/bin/bash
# fetch_data.sh

DATA=$(curl -s https://api.example.com/data)
echo "{\"data\": $DATA, \"status\": \"success\"}"
```

## MCP Tool Integration

### Using MCP Tools

```crystal
workflow "mcp-tools" do
  # Call MCP tool
  exec "mcp:filesystem_read",
    attributes: {
      path: "/path/to/file.txt"
    }
  
  agent "analyzer",
    prompt: "Analyze the file content"
end
```

### MCP Resource Access

```crystal
workflow "mcp-resources" do
  # Access MCP resource
  exec "mcp:database_query",
    attributes: {
      query: "SELECT * FROM users"
    }
  
  agent "data-processor"
end
```

## Custom Node Kinds

Register and use custom Crystal functions:

**Register**:

```crystal
Ocawe::RegistryApi.node_kind("custom_validator") do |ctx, attributes|
  input = attributes["input"]?
  valid = validate_data(input)
  
  {
    "valid" => JSON.parse(valid.to_json),
    "errors" => JSON.parse(errors.to_json)
  }
end
```

**Use in workflow**:

```crystal
workflow "custom-node-workflow" do
  custom_validator input: input.data
  
  if state.custom_validator_valid
    agent "processor"
  else
    agent "error-handler"
  end
end
```

## Best Practices

### Keep Workflows Focused

**Good** - Single responsibility:

```crystal
workflow "user-onboarding" do
  agent "welcome-email-generator"
  agent "account-setup-guide"
  agent "first-task-suggester"
end
```

**Bad** - Too many responsibilities:

```crystal
workflow "everything" do
  agent "onboarding"
  agent "billing"
  agent "support"
  agent "analytics"
end
```

### Use Parallel When Possible

**Sequential** (slow):

```crystal
workflow "slow" do
  agent "analyzer-1"  # 5 seconds
  agent "analyzer-2"  # 5 seconds
  agent "analyzer-3"  # 5 seconds
end
# Total: 15 seconds
```

**Parallel** (fast):

```crystal
workflow "fast" do
  parallel do
    agent "analyzer-1"  # 5 seconds
    agent "analyzer-2"  # 5 seconds
    agent "analyzer-3"  # 5 seconds
  end
end
# Total: 5 seconds
```

### Handle Errors Gracefully

```crystal
workflow "error-handling" do
  agent "risky-operation"
  
  if state.risky_operation_failed
    # Log error
    exec "log_error.sh",
      runtime: {shell: "bash"},
      env: {ERROR: state.risky_operation_error}
    
    # Attempt recovery
    agent "recovery-agent"
    
    # Notify if recovery fails
    if state.recovery_failed
      exec "notify_admin.sh",
        runtime: {shell: "bash"}
    end
  end
end
```

### Use Schema Validation

```crystal
workflow "validated" do
  agent "input-validator",
    input_schema: schema_ref("input"),
    output_schema: schema_ref("output")
  
  agent "processor",
    input_schema: schema_ref("processor_input")
end
```

### Document Complex Logic

```crystal
workflow "complex-logic" do
  # Phase 1: Data Collection
  # Fetch from multiple sources in parallel
  parallel do
    exec "fetch_api_data.sh", runtime: {shell: "bash"}
    exec "fetch_db_data.sh", runtime: {shell: "bash"}
    exec "fetch_file_data.sh", runtime: {shell: "bash"}
  end
  
  # Phase 2: Validation
  # Ensure data quality before processing
  agent "data-validator"
  
  # Phase 3: Processing
  # Main business logic
  if state.data_validator_passed
    agent "data-processor"
  else
    suspend "data-review",
      reason: "Data validation failed"
  end
end
```

## Workflow Lifecycle

### Workflow States

- `running` - Workflow is executing
- `completed` - Successfully finished
- `failed` - Error occurred
- `suspended` - Waiting for resume
- `paused` - Manually paused (future)

### Monitoring Workflows

**Get workflow status**:

```bash
GET /v1/workflows/{workflowId}/runs/{runId}
```

**List all runs**:

```bash
GET /v1/workflows/{workflowId}/runs
```

**Get workflow definition**:

```bash
GET /v1/workflows/{workflowId}
```

## API Reference

### Trigger Workflow

**POST** `/v1/triggers/workflows/{workflowId}`

Request:

```json
{
  "input": {
    "topic": "Crystal programming",
    "detail_level": "comprehensive"
  },
  "resources": {
    "api_key": "secret"
  }
}
```

Response:

```json
{
  "run_id": "run-abc123",
  "status": "completed",
  "output": {
    "result": "..."
  }
}
```

### Create Workflow Run

**POST** `/v1/workflows/{workflowId}/runs`

### Resume Workflow

**POST** `/v1/workflows/{workflowId}/runs/{runId}/resume`

Request:

```json
{
  "approved": true,
  "feedback": "Looks good"
}
```

## Next Steps

- **[Agents Guide](/guides/agents)** - Deep dive into agents
- **[Tools Guide](/guides/tools)** - Create custom tools
- **[Workflow Format](/guides/workflow-format)** - Complete DSL reference
- **[Examples](/guides/examples)** - Working examples
- **[API Reference](/api/reference)** - Complete API docs
