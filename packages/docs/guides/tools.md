# Tools Guide

Extend agent and workflow capabilities with custom tools, MCP integrations, and external scripts. Tools enable agents to perform actions and access external resources.

## What are Tools?

Tools are functions that agents can call to:
- Query databases
- Call external APIs
- Read/write files
- Perform calculations
- Execute custom business logic
- Access external resources

## Tool Types in Ocawe

### 1. External Scripts

Shell scripts, Python, Ruby, or any executable:

```crystal
workflow "script-tool" do
  exec "tools/fetch_data.sh",
    runtime: {shell: "bash"},
    env: {
      API_KEY: "secret",
      BASE_URL: "https://api.example.com"
    }
end
```

### 2. MCP Tools

Model Context Protocol integrations:

```crystal
workflow "mcp-tool" do
  exec "mcp:filesystem_read",
    attributes: {
      path: "/path/to/file.txt"
    }
end
```

### 3. Internal Functions (NodeKind)

Crystal-native functions registered via RegistryAPI:

```crystal
Ocawe::RegistryApi.node_kind("custom_tool") do |ctx, attributes|
  # Custom Crystal logic
  {
    "result" => JSON.parse("success".to_json)
  }
end
```

## Creating External Script Tools

### Basic Shell Script Tool

**`tools/weather.sh`**:

```bash
#!/bin/bash

# Tool must output JSON to stdout
CITY=$1
TEMP=$(curl -s "https://api.weather.com/current?city=$CITY" | jq .temperature)

echo "{\"city\": \"$CITY\", \"temperature\": $TEMP, \"unit\": \"celsius\"}"
```

**Usage in workflow**:

```crystal
workflow "weather-check" do
  exec "tools/weather.sh",
    runtime: {
      shell: "bash",
      args: [input.city]
    }
  
  agent "weather-reporter",
    prompt: "Report the weather in a friendly way"
end
```

### Python Tool

**`tools/analyze_sentiment.py`**:

```python
#!/usr/bin/env python3

import sys
import json
from textblob import TextBlob

def analyze_sentiment(text):
    blob = TextBlob(text)
    polarity = blob.sentiment.polarity
    
    if polarity > 0.1:
        sentiment = "positive"
    elif polarity < -0.1:
        sentiment = "negative"
    else:
        sentiment = "neutral"
    
    return {
        "sentiment": sentiment,
        "polarity": polarity,
        "subjectivity": blob.sentiment.subjectivity
    }

if __name__ == "__main__":
    text = sys.argv[1]
    result = analyze_sentiment(text)
    # Must output JSON
    print(json.dumps(result))
```

**Usage**:

```crystal
workflow "sentiment-analysis" do
  exec "tools/analyze_sentiment.py",
    runtime: {
      command: "python3",
      args: [input.text]
    }
  
  if state.analyze_sentiment_sentiment == "negative"
    agent "crisis-handler"
  end
end
```

### Inline Script Tool

For simple scripts, use inline execution:

```crystal
workflow "inline-tool" do
  exec """
    #!/bin/bash
    DATA=$(date +%s)
    echo "{\"timestamp\": $DATA, \"status\": \"ok\"}"
  """,
    runtime: {shell: "bash"}
end
```

### Tool Environment Variables

Pass secrets and configuration:

```crystal
workflow "secure-tool" do
  exec "tools/api_call.sh",
    runtime: {shell: "bash"},
    env: {
      API_KEY: state.resources.api_key,
      API_SECRET: state.resources.api_secret,
      ENDPOINT: "https://api.example.com"
    }
end
```

## MCP Tool Integration

### What is MCP?

Model Context Protocol (MCP) provides a standardized way to connect AI systems with external tools and data sources.

### Registering MCP Servers

**Via API**:

```bash
curl -X POST http://localhost:4111/v1/mcp/servers \
  -H "Content-Type: application/json" \
  -d '{
    "name": "filesystem",
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/workspace"],
    "env": {}
  }'
```

**Via Configuration**:

```json
{
  "mcp": {
    "servers": {
      "filesystem": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"]
      },
      "database": {
        "command": "mcp-server-postgres",
        "env": {
          "DATABASE_URL": "postgres://..."
        }
      }
    }
  }
}
```

### Using MCP Tools

**List available MCP tools**:

```bash
GET /v1/mcp/catalog/tools
```

**Use MCP tool in workflow**:

```crystal
workflow "mcp-workflow" do
  # Read file via MCP
  exec "mcp:read_file",
    attributes: {
      path: "/workspace/data.json"
    }
  
  # Agent processes file content
  agent "data-analyzer"
  
  # Write results via MCP
  exec "mcp:write_file",
    attributes: {
      path: "/workspace/results.json",
      content: state.data_analyzer_output
    }
end
```

### MCP Resources

Access external resources:

```crystal
workflow "mcp-resources" do
  # Query database via MCP
  exec "mcp:postgres_query",
    attributes: {
      query: "SELECT * FROM users WHERE active = true"
    }
  
  agent "user-analyzer",
    prompt: "Analyze user data and provide insights"
end
```

### MCP Prompts

Use predefined MCP prompts:

```bash
GET /v1/mcp/catalog/prompts
```

```crystal
workflow "mcp-prompts" do
  exec "mcp:code_review_prompt",
    attributes: {
      code: input.code,
      language: "crystal"
    }
  
  agent "code-reviewer"
end
```

### Managing MCP Servers

**List servers**:

```bash
GET /v1/mcp/servers
```

**Get server details**:

```bash
GET /v1/mcp/servers/{serverId}
```

**Update server**:

```bash
PATCH /v1/mcp/servers/{serverId}
```

**Delete server**:

```bash
DELETE /v1/mcp/servers/{serverId}
```

**Reconnect server**:

```bash
POST /v1/mcp/servers/{serverId}/reconnect
```

## Custom Crystal Tools (NodeKind)

### Registering Custom Tools

**Simple tool**:

```crystal
Ocawe::RegistryApi.node_kind("calculator") do |ctx, attributes|
  operation = attributes["operation"]?.try(&.as_s) || "add"
  a = attributes["a"]?.try(&.as_i) || 0
  b = attributes["b"]?.try(&.as_i) || 0
  
  result = case operation
  when "add"
    a + b
  when "subtract"
    a - b
  when "multiply"
    a * b
  when "divide"
    a / b
  else
    0
  end
  
  {
    "result" => JSON.parse(result.to_json),
    "operation" => JSON.parse(operation.to_json)
  }
end
```

**Use in workflow**:

```crystal
workflow "calculation" do
  calculator operation: "add", a: 10, b: 20
  
  agent "result-reporter",
    prompt: "Report the calculation result: #{state.calculator_result}"
end
```

### Database Query Tool

```crystal
Ocawe::RegistryApi.node_kind("db_query") do |ctx, attributes|
  query = attributes["query"]?.try(&.as_s) || ""
  
  db = DB.open(ENV["DATABASE_URL"])
  results = db.query_all(query, as: Hash(String, JSON::Any))
  db.close
  
  {
    "results" => JSON.parse(results.to_json),
    "count" => JSON.parse(results.size.to_json)
  }
end
```

```crystal
workflow "database-analysis" do
  db_query query: "SELECT * FROM orders WHERE status = 'pending'"
  
  agent "order-analyzer",
    prompt: "Analyze pending orders and suggest actions"
end
```

### HTTP API Tool

```crystal
Ocawe::RegistryApi.node_kind("api_call") do |ctx, attributes|
  url = attributes["url"]?.try(&.as_s) || ""
  method = attributes["method"]?.try(&.as_s) || "GET"
  
  response = HTTP::Client.exec(method, url)
  
  {
    "status" => JSON.parse(response.status_code.to_json),
    "body" => JSON.parse(response.body)
  }
end
```

```crystal
workflow "api-integration" do
  api_call url: "https://api.example.com/data", method: "GET"
  
  agent "data-processor"
end
```

### File Operations Tool

```crystal
Ocawe::RegistryApi.node_kind("file_ops") do |ctx, attributes|
  operation = attributes["operation"]?.try(&.as_s) || "read"
  path = attributes["path"]?.try(&.as_s) || ""
  
  result = case operation
  when "read"
    File.read(path)
  when "write"
    content = attributes["content"]?.try(&.as_s) || ""
    File.write(path, content)
    "success"
  when "delete"
    File.delete(path)
    "deleted"
  else
    "unknown operation"
  end
  
  {
    "result" => JSON.parse(result.to_json),
    "operation" => JSON.parse(operation.to_json),
    "path" => JSON.parse(path.to_json)
  }
end
```

## Tool Best Practices

### 1. Always Output JSON

Tools must output valid JSON to stdout:

```bash
# Good
echo '{"result": "success", "data": [1, 2, 3]}'

# Bad - not JSON
echo "Success: 123"
```

### 2. Handle Errors Gracefully

```bash
#!/bin/bash

set -e

if [ -z "$1" ]; then
  echo '{"error": "Missing required parameter", "status": "failed"}'
  exit 1
fi

# Tool logic...

echo '{"status": "success", "result": "..."}'
```

### 3. Use Environment Variables for Secrets

```crystal
workflow "secure" do
  exec "tools/api_call.sh",
    runtime: {shell: "bash"},
    env: {
      API_KEY: state.resources.api_key  # From workflow resources
    }
end
```

Never hardcode secrets in scripts!

### 4. Document Tool Interfaces

```bash
#!/bin/bash
# weather.sh - Fetches current weather for a city
#
# Usage: weather.sh <city>
#
# Output JSON schema:
# {
#   "city": string,
#   "temperature": number,
#   "unit": "celsius" | "fahrenheit",
#   "conditions": string
# }

CITY=$1
# ...
```

### 5. Make Tools Idempotent

```crystal
Ocawe::RegistryApi.node_kind("create_user") do |ctx, attributes|
  email = attributes["email"]?.try(&.as_s)
  
  # Check if user already exists
  existing = db.query_one?("SELECT id FROM users WHERE email = ?", email)
  
  if existing
    # Return existing user instead of error
    {
      "user_id" => existing,
      "created" => JSON.parse(false.to_json)
    }
  else
    # Create new user
    user_id = db.exec("INSERT INTO users (email) VALUES (?)", email)
    {
      "user_id" => user_id,
      "created" => JSON.parse(true.to_json)
    }
  end
end
```

### 6. Validate Inputs

```crystal
Ocawe::RegistryApi.node_kind("validated_tool") do |ctx, attributes|
  input = attributes["input"]?.try(&.as_s)
  
  # Validate input
  unless input && input.size > 0
    raise "Invalid input: must be non-empty string"
  end
  
  # Process...
  {
    "result" => JSON.parse("success".to_json)
  }
end
```

## Tool Examples

### Database Integration

```crystal
workflow "user-management" do
  # Query users
  db_query query: "SELECT * FROM users WHERE active = true"
  
  # Analyze with agent
  agent "user-analyzer",
    prompt: "Analyze user patterns and suggest retention strategies"
  
  # Update database based on analysis
  db_query query: "UPDATE users SET risk_score = ? WHERE id = ?",
    params: [state.user_analyzer_risk_score, input.user_id]
end
```

### External API Integration

```crystal
workflow "api-workflow" do
  # Fetch data from external API
  api_call url: "https://api.example.com/products",
    method: "GET",
    headers: {
      Authorization: "Bearer #{state.resources.api_token}"
    }
  
  # Process data with agent
  agent "product-analyzer"
  
  # Send results back to API
  api_call url: "https://api.example.com/analysis",
    method: "POST",
    body: state.product_analyzer_output
end
```

### File Processing Pipeline

```crystal
workflow "file-pipeline" do
  # Read input file
  file_ops operation: "read", path: input.file_path
  
  # Process with agent
  agent "document-processor"
  
  # Write output file
  file_ops operation: "write",
    path: input.output_path,
    content: state.document_processor_output
end
```

### Multi-Tool Orchestration

```crystal
workflow "complex-workflow" do
  parallel do
    # Multiple data sources in parallel
    api_call url: "https://api1.example.com/data"
    db_query query: "SELECT * FROM local_data"
    file_ops operation: "read", path: "/data/file.json"
  end
  
  # Agent synthesizes all data
  agent "data-synthesizer",
    prompt: "Combine data from all sources and create unified report"
  
  # Store results
  db_query query: "INSERT INTO reports (data) VALUES (?)",
    params: [state.data_synthesizer_output]
  
  # Notify via API
  api_call url: "https://notify.example.com/webhook",
    method: "POST",
    body: {report_id: state.last_insert_id}
end
```

## Tool Discovery

### List Available Tools

```bash
# List all tools
GET /v1/tools

# List MCP tools
GET /v1/mcp/catalog/tools

# List registered NodeKind functions
GET /v1/functions
```

### Tool Metadata

Tools can provide metadata for discovery:

```crystal
Ocawe::RegistryApi.node_kind("calculator",
  description: "Performs basic arithmetic operations",
  parameters: {
    "operation" => "add | subtract | multiply | divide",
    "a" => "number",
    "b" => "number"
  },
  returns: {
    "result" => "number"
  }
) do |ctx, attributes|
  # Tool implementation...
end
```

## Debugging Tools

### Enable Tool Logging

```crystal
workflow "debug-tools" do
  @[Logger(level: "debug")]
  
  exec "tools/debug_tool.sh",
    runtime: {shell: "bash"}
end
```

### Test Tools Independently

```bash
# Test shell script directly
./tools/weather.sh "San Francisco"

# Test Python tool
python3 tools/analyze_sentiment.py "I love Crystal!"

# Test MCP tool via API
curl -X POST http://localhost:4111/v1/mcp/tools/read_file \
  -H "Content-Type: application/json" \
  -d '{"path": "/workspace/test.txt"}'
```

### Tool Error Handling

```crystal
workflow "error-handling" do
  exec "tools/risky_tool.sh",
    runtime: {shell: "bash"}
  
  if state.risky_tool_error
    agent "error-handler",
      prompt: "Handle tool error: #{state.risky_tool_error}"
  end
end
```

## Advanced Tool Patterns

### Retry Logic

```crystal
workflow "retry-tool" do
  retry_count = 0
  
  while retry_count < 3 do
    api_call url: "https://unreliable-api.com/data"
    
    if state.api_call_success
      break
    end
    
    retry_count += 1
    sleep 5  # Wait before retry
  end
end
```

### Tool Composition

```crystal
workflow "composed-tools" do
  # Tool 1: Fetch raw data
  api_call url: "https://api.example.com/raw"
  
  # Tool 2: Transform data
  data_transformer input: state.api_call_body
  
  # Tool 3: Store transformed data
  db_query query: "INSERT INTO transformed_data VALUES (?)",
    params: [state.data_transformer_output]
end
```

### Conditional Tool Selection

```crystal
workflow "dynamic-tools" do
  agent "router",
    prompt: "Decide which data source to use"
  
  if state.router_decision == "api"
    api_call url: "https://api.example.com/data"
  elsif state.router_decision == "database"
    db_query query: "SELECT * FROM data"
  else
    file_ops operation: "read", path: "/data/file.json"
  end
end
```

## Next Steps

- **[Agents Guide](/guides/agents)** - Build intelligent agents
- **[Workflows Guide](/guides/workflows)** - Orchestrate tools and agents
- **[MCP Documentation](/guides/mcp)** - Deep dive into MCP
- **[Registry API](/guides/registry)** - Register custom NodeKinds
- **[API Reference](/api/reference)** - Complete API docs
