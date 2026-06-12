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

## Agent Client Protocol (ACP)

Execute external AI agents via the Agent Client Protocol (ACP). ACP enables integration with third-party agents (Codex, Claude, etc.) through a standardized JSON-RPC 2.0 protocol.

### Basic ACP Execution

```crystal
workflow "acp-agent" do
  exec "codex",
    runtime: {
      "acp" => {
        "command" => "codex",
        "args" => ["--server"]
      }
    }
end
```

### ACP with Environment Variables

```crystal
workflow "acp-with-env" do
  exec "claude",
    runtime: {
      "acp" => {
        "command" => "claude",
        "args" => ["--server"],
        "env" => {
          "API_KEY" => "your-key"
        }
      }
    }
end
```

### ACP with Custom Working Directory

```crystal
workflow "acp-custom-cwd" do
  exec "codex",
    runtime: {
      "acp" => {
        "command" => "codex",
        "cwd" => "/project/workspace"
      }
    }
end
```

### ACP in Multi-Step Workflows

```crystal
workflow "acp-pipeline" do
  # Step 1: Research with external agent
  exec "researcher",
    runtime: {
      "acp" => {
        "command" => "codex",
        "args" => ["--server"]
      }
    }

  # Step 2: Analyze with local agent
  agent "analyzer",
    prompt: "Analyze the research findings"

  # Step 3: Generate report with external agent
  exec "reporter",
    runtime: {
      "acp" => {
        "command" => "claude"
      }
    }
end
```

### ACP Configuration Options

| Option | Type | Description |
|--------|------|-------------|
| `command` | String | The command to start the ACP agent |
| `args` | Array(String) | Arguments to pass to the command |
| `cwd` | String | Working directory for the agent process |
| `env` | Hash(String, String) | Environment variables for the agent |
| `metadata` | Hash | Additional metadata passed to the agent |

### ACP Protocol Flow

1. **Initialize**: Ocawe sends `initialize` request to discover agent capabilities
2. **Session Creation**: Creates a new session with `session/new`
3. **Prompt**: Sends user input via `session/prompt` with content blocks
4. **Updates**: Receives streaming `session/update` notifications
5. **Completion**: Receives final `session/prompt` response with stop reason
6. **Cleanup**: Closes connection and terminates agent process

### ACP Output Format

ACP execution produces a structured output:

```json
{
  "session_id": "sess_abc123",
  "stop_reason": "end_turn",
  "content": "Generated response text",
  "message": "Generated response text",
  "metadata": {}
}
```

| Field | Description |
|-------|-------------|
| `session_id` | Unique session identifier |
| `stop_reason` | Why the agent stopped (end_turn, max_tokens, etc.) |
| `content` | The generated text content |
| `message` | Human-readable message |
| `metadata` | Any metadata from the ACP configuration |

### Building ACP-Compatible Agents

Your agent must implement the JSON-RPC 2.0 protocol:

```ruby
# Example ACP agent (Ruby)
loop do
  line = STDIN.gets
  break unless line

  req = JSON.parse(line)

  case req["method"]
  when "initialize"
    # Return capabilities
    puts({
      jsonrpc: "2.0",
      id: req["id"],
      result: {
        protocolVersion: 1,
        agentInfo: {
          name: "my-agent",
          version: "1.0.0"
        }
      }
    }.to_json)

  when "session/new"
    # Create session
    puts({
      jsonrpc: "2.0",
      id: req["id"],
      result: { sessionId: "sess_123" }
    }.to_json)

  when "session/prompt"
    # Process prompt and stream updates
    session_id = req["params"]["sessionId"]
    prompt = req["params"]["prompt"]

    # Send content update
    puts({
      jsonrpc: "2.0",
      method: "session/update",
      params: {
        sessionId: session_id,
        update: {
          sessionUpdate: "agent_message_chunk",
          content: {
            type: "text",
            text: "Response content"
          }
        }
      }
    }.to_json)

    # Send final response
    puts({
      jsonrpc: "2.0",
      id: req["id"],
      result: { stopReason: "end_turn" }
    }.to_json)
  end

  STDOUT.flush
end
```

## ActivityPub Federation

### Follow Remote Actors

Subscribe to remote ActivityPub actors for federation:

```crystal
workflow "federated-agent" do
  # Follow one or more remote actors
  follow ["@agent@example.com", "@bot@social.domain"]
  
  agent "processor"
end
```

The `follow` method:
- Registers ActivityPub subscriptions with remote actors
- Polls their outboxes for new activities
- Integrates with the framework's federation system
- Supports both `@handle@domain` format and full actor URLs

**Multiple subscriptions**:

```crystal
workflow "multi-feed" do
  follow [
    "@news@feeds.com",
    "@alerts@monitoring.io",
    "https://custom.domain/actors/special-bot"
  ]
  
  # Process incoming federation activities
  agent "activity-handler",
    prompt: "Handle incoming ActivityPub activities"
end
```

**Use cases**:
- Subscribe to remote AI agents for collaborative workflows
- Monitor ActivityPub feeds for events
- Integrate with ForgeFed repositories for CI/CD
- Build federated multi-agent systems

The federation system automatically:
- Resolves actor documents via WebFinger
- Establishes outbox polling subscriptions
- Delivers responses back via ActivityPub inbox
- Handles HTTP signatures and authentication

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

## Workflow as Model

Execute workflows through the OpenAI-compatible `/v1/chat/completions` API by referencing them as models.

### Using Workflows as Chat Models

Any registered workflow can be used as a model in chat completions:

```bash
curl -X POST http://localhost:4111/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "workflow/my-workflow",
    "messages": [
      {"role": "user", "content": "Hello, process this request"}
    ]
  }'
```

### Workflow Model Format

Prefix any workflow ID with `workflow/` to use it as a model:

```json
{
  "model": "workflow/customer-support",
  "messages": [...]
}
```

### Input Mapping

The workflow receives the chat input as structured data:

```json
{
  "prompt": "User message content",
  "messages": [
    {"role": "user", "content": "Hello"}
  ],
  "system": "Optional system message"
}
```

### Output Format

The workflow output is returned as a chat completion response:

```json
{
  "id": "chatcmpl_abc123",
  "object": "chat.completion",
  "created": 1716234567,
  "model": "workflow/my-workflow",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Workflow output text"
      },
      "finish_reason": "stop"
    }
  ]
}
```

### Use Cases

- **Customer Support**: Deploy a support workflow as a chat model
- **Content Generation**: Use content workflows via standard chat APIs
- **Data Processing**: Chain workflows through existing chat clients
- **Multi-Agent Systems**: Combine multiple workflow models in a single chat

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
