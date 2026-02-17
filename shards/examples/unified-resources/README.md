# Unified Resources Example

This example demonstrates the unified resource management features introduced in v1.1.0.

## Features Demonstrated

### 1. `@[Resources(...)]` Annotation

```crystal
@[Resources(model: "openai/gpt-4.1", skill: ["translation", "summarization"], tool: ["http-client"])]
```

This provides a unified approach that supports:
- Models
- Skills (single or array)
- Tools (single or array)

### 2. Parallel Execution

```crystal
parallel do
  agent "translator"
  agent "summarizer"
end
```

The `parallel do...end` block executes contained agents concurrently, improving workflow performance for independent operations.

## Workflow Structure

1. **Analyzer** - Extracts key information from input
2. **Processor** - Prepares content for parallel processing
3. **Parallel Block**
   - **Translator** - Translates content
   - **Summarizer** - Creates summary
4. **Synthesizer** - Combines parallel outputs

## Running

```bash
cogni run unified-resources
```
