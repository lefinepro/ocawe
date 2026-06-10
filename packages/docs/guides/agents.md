# Agents Guide

Build intelligent agents with LLM capabilities, tools, guardrails, and memory. Agents are the core building blocks for AI-powered workflows in Ocawe.

## What are Agents?

Agents are LLM-powered nodes that:
- Process natural language inputs
- Make decisions based on context
- Call tools to perform actions
- Generate structured or unstructured outputs
- Maintain conversation memory

## When to Use Agents

**Use agents when you need:**
- Natural language understanding
- Dynamic decision making
- Tool usage (API calls, database queries, etc.)
- Contextual responses
- Multi-turn conversations

**Don't use agents when:**
- You need deterministic logic (use workflows)
- You have simple data transformations (use tools)
- You want predictable control flow (use workflow primitives)

## Creating Your First Agent

### Agent Definition File

Create an agent markdown file in `agents/` directory:

**`agents/assistant.md`**:

```markdown
---
description: "General purpose assistant"
model: "openai/gpt-4"
voice:
  voice_operator: "openai"
guardrails:
  input:
    blocked_terms: ["forbidden", "banned"]
---

You are a helpful assistant. Answer questions concisely and accurately.
Provide examples when helpful.
```

### Using the Agent

**In workflow**:

```crystal
workflow "example" do
  agent "assistant"
end
```

**Via Trigger API**:

```bash
curl -X POST http://localhost:4111/v1/triggers/agents/assistant \
  -H "Content-Type: application/json" \
  -d '{"input": {"query": "What is Crystal?"}}'
```

**Via CLI**:

```bash
./build/ocawe agent assistant --prompt "What is Crystal?"
```

## Agent Configuration

### Model Selection

Specify the LLM model in agent frontmatter or workflow DSL:

**In agent file**:

```markdown
---
model: "openai/gpt-4"
---
```

**In workflow** (overrides agent file):

```crystal
workflow "example" do
  agent "assistant",
    model: "anthropic/claude-3-opus"
end
```

**Supported providers**:
- OpenAI: `openai/gpt-4`, `openai/gpt-4-turbo`, `openai/gpt-3.5-turbo`
- Anthropic: `anthropic/claude-3-opus`, `anthropic/claude-3-sonnet`
- Local models: `clipproxyapi/qwen3-coder-plus`
- Custom endpoints via configuration

### Custom Prompts

**Override system prompt**:

```crystal
workflow "example" do
  agent "assistant",
    prompt: "You are a code review expert. Provide detailed feedback."
end
```

**Dynamic prompts from input**:

```crystal
workflow "dynamic-prompt" do
  agent "assistant",
    prompt: "Answer as a #{input.role} expert"
end
```

## Schema Validation

Type-safe input and output validation using Crystal schemas.

### Input Schema

**Define in agent file**:

````markdown
---
description: "Validator agent"
---

```crystal schema:input
Schema::Types.object({
  "query" => Schema::Types.of(String),
  "language" => Schema::Types.of(String, optional: true)
}, strict: true)
```
````

**Use in workflow**:

```crystal
workflow "validated" do
  agent "validator",
    input_schema: schema_ref("input")
end
```

### Output Schema

**Enforce structured output**:

````markdown
```crystal schema:output
Schema::Types.object({
  "answer" => Schema::Types.of(String),
  "confidence" => Schema::Types.of(Float64),
  "sources" => Schema::Types.array(Schema::Types.of(String))
}, strict: true)
```
````

```crystal
workflow "structured-output" do
  agent "validator",
    output_schema: schema_ref("output")
end
```

### Resume Schema

**For suspend/resume workflows**:

````markdown
```crystal schema:resume
Schema::Types.object({
  "approved" => Schema::Types.of(Bool),
  "feedback" => Schema::Types.of(String, optional: true)
}, strict: true)
```
````

```crystal
workflow "approval-flow" do
  agent "analyzer"
  
  suspend "approval",
    reason: "Requires review",
    resume_schema: schema_ref("resume")
  
  agent "executor"
end
```

## Guardrails

Protect your agents with input/output guardrails.

### Input Guardrails

**Block specific terms**:

```markdown
---
guardrails:
  input:
    blocked_terms:
      - "forbidden"
      - "banned"
      - "illegal"
---
```

**Custom validation** (via runtime extension):

```crystal
Ocawe::RegistryApi.input_guardrail("no_pii") do |input|
  # Detect and reject PII in input
  if contains_email?(input) || contains_phone?(input)
    raise "PII detected in input"
  end
end
```

### Output Guardrails

**Validate agent responses**:

```crystal
Ocawe::RegistryApi.output_guardrail("content_safety") do |output|
  # Check for harmful content
  if contains_harmful_content?(output)
    raise "Harmful content detected"
  end
end
```

When guardrails fail, workflow returns `422` with error envelope:

```json
{
  "error": "workflow_error",
  "message": "Guardrail violation: blocked term detected"
}
```

## Agent Tools

Agents can use tools to perform actions and retrieve information.

### Automatic Tool Access

Agents automatically have access to:
- Registered MCP tools
- Custom NodeKind functions
- External scripts via `exec`

### Tool Usage in Prompts

**Guide agents to use tools**:

```markdown
---
description: "Data analyst agent"
---

You are a data analyst. You have access to:
- `query_database` - Query the PostgreSQL database
- `generate_chart` - Create visualizations
- `fetch_external_data` - Get data from APIs

When asked about data, use these tools to provide accurate information.
```

### Tool Results in Context

Tool results are automatically included in agent context:

```crystal
workflow "tool-flow" do
  # Tool execution
  exec "tools/fetch_data.sh",
    runtime: {shell: "bash"}
  
  # Agent receives tool output in input
  agent "analyzer",
    prompt: "Analyze the data from the previous step"
end
```

## Voice Integration

Enable voice input/output for agents.

### Voice Configuration

**In agent file**:

```markdown
---
voice:
  voice_operator: "openai"
  stt_model: "whisper-1"
  tts_model: "tts-1"
  voice: "alloy"
---
```

### Voice Workflow

```crystal
workflow "voice-assistant" do
  # Agent processes voice input
  agent "assistant"
  
  # Voice output
  voice "speak",
    voice_operator: "openai",
    text: state.assistant_response
end
```

**Supported voice operators**:
- OpenAI (Whisper + TTS)
- ElevenLabs
- Azure Speech Services
- Google Cloud Text-to-Speech

## Memory & State

### Workflow State

Agents automatically receive workflow state in their context:

```crystal
workflow "stateful-agent" do
  agent "step-1"
  # Output: {"analysis": "..."}
  
  agent "step-2"
  # Receives: input = <step-1 output>
  # Can reference previous steps via state
end
```

### Multi-Agent Memory

Share memory across agents in a workflow:

```crystal
workflow "multi-agent-memory" do
  agent "researcher",
    prompt: "Research the topic and store findings"
  
  # Memory from researcher is available to analyst
  agent "analyst",
    prompt: "Analyze the research findings"
  
  # Both agents' context available to reporter
  agent "reporter",
    prompt: "Create a report from research and analysis"
end
```

### Persistent Memory (Coming Soon)

```crystal
workflow "persistent-memory" do
  agent "assistant",
    memory: {
      thread_id: input.user_id,
      scope: "user"
    }
end
```

## Advanced Patterns

### Multi-Turn Conversations

```crystal
workflow "conversation" do
  loop do
    agent "assistant"
    
    suspend "user-input",
      reason: "Waiting for user response"
  end
end
```

### Agent Delegation

```crystal
workflow "supervisor" do
  agent "supervisor",
    prompt: "Decide which specialist to delegate to"
  
  if state.supervisor_decision == "technical"
    agent "technical-specialist"
  elsif state.supervisor_decision == "business"
    agent "business-specialist"
  end
end
```

### Parallel Agent Processing

```crystal
workflow "parallel-agents" do
  parallel do
    agent "sentiment-analyzer"
    agent "topic-extractor"
    agent "entity-recognizer"
  end
  
  agent "synthesizer",
    prompt: "Synthesize all analysis results"
end
```

### Iterative Refinement

```crystal
workflow "iterative-refinement" do
  agent "draft-generator"
  
  while state.quality_score < 0.9 do
    agent "critic",
      prompt: "Review and suggest improvements"
    
    agent "refiner",
      prompt: "Apply suggested improvements"
  end
end
```

## Best Practices

### Prompt Engineering

**Be specific and clear**:

```markdown
# Good
You are a senior software engineer specializing in Crystal.
Provide code reviews focusing on:
1. Type safety
2. Performance
3. Idiomatic Crystal patterns

# Bad
You are a code reviewer.
```

**Provide examples**:

```markdown
When analyzing code, structure your response like this:

**Summary**: Brief overview
**Issues**: List of problems found
**Suggestions**: Concrete improvements
**Example**: Code snippet showing recommended changes
```

**Set boundaries**:

```markdown
Only answer questions about Crystal programming.
For other topics, politely decline and redirect to appropriate resources.
```

### Error Handling

**Handle agent failures gracefully**:

```crystal
workflow "resilient-agent" do
  agent "primary-agent"
  
  # Fallback if primary fails
  if state.primary_agent_failed
    agent "fallback-agent",
      prompt: "Provide a simpler response"
  end
end
```

### Performance Optimization

**Use appropriate models**:

```crystal
# Fast, cheap model for simple tasks
agent "classifier",
  model: "openai/gpt-3.5-turbo"

# Powerful model for complex reasoning
agent "analyzer",
  model: "anthropic/claude-3-opus"
```

**Parallel processing**:

```crystal
# Process multiple items concurrently
parallel do
  agent "process-item-1"
  agent "process-item-2"
  agent "process-item-3"
end
```

## API Reference

### Agent Trigger API

**POST** `/v1/triggers/agents/{agentId}`

Request:

```json
{
  "input": {
    "query": "What is Crystal?",
    "context": "programming language"
  }
}
```

Response:

```json
{
  "output": {
    "response": "Crystal is a statically-typed, compiled language...",
    "confidence": 0.95
  },
  "metadata": {
    "model": "openai/gpt-4",
    "tokens": 150
  }
}
```

### Agent Generation API

**POST** `/v1/agents/{agentId}/generate`

For streaming responses:

```bash
curl -X POST http://localhost:4111/v1/agents/assistant/generate \
  -H "Content-Type: application/json" \
  -d '{"input": {"query": "Explain async/await"}}' \
  --no-buffer
```

## Next Steps

- **[Workflows Guide](/guides/workflows)** - Orchestrate multiple agents
- **[Tools Guide](/guides/tools)** - Extend agent capabilities
- **[Memory Guide](/guides/memory)** - Add persistent memory
- **[Voice Guide](/guides/voice)** - Enable voice interactions
- **[API Reference](/api/reference)** - Complete API documentation
