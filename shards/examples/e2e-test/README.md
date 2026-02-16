# E2E Test Workflow Example

This workflow bundle demonstrates comprehensive end-to-end testing scenarios for CogniCore.

## Features Demonstrated

- **Model API Configuration**: Uses `clipproxyapi/qwen3-coder-model` (configurable via environment)
- **Agent Execution**: Full agent with input/output schema validation
- **Guardrails**: Input blocking and output length validation
- **Approval Nodes**: Human-in-the-loop checkpoint
- **RAG Operations**: Vector store query integration
- **Voice Integration**: Text-to-speech synthesis

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `COGNI_E2E_MODEL` | Model to use for E2E tests | `clipproxyapi/qwen3-coder-model` |
| `CLIPROXY_API_KEY` | API key for clipproxy service | (required for real API) |
| `COGNICORE_MOCK_LLM` | Set to `1` to use mock responses | - |

### Secrets (GitHub Actions)

For CI/CD, store the following secrets:
- `CLIPROXY_API_KEY`: API key for the clipproxy model service

## Running the Workflow

### Local Development

```bash
# Build the CLI
crystal build src/cli/main.cr -o build/cogni

# Run with mock (no API calls)
COGNICORE_MOCK_LLM=1 ./build/cogni up --port 4111 --workflows-root ./shards/examples/e2e-test

# Run with real API
CLIPROXY_API_KEY=your-key ./build/cogni up --port 4111 --workflows-root ./shards/examples/e2e-test
```

### API Usage

```bash
# Start a workflow run
curl -X POST http://localhost:4111/v1/workflows/e2e-test/runs \
  -H 'content-type: application/json' \
  -d '{"input_data": {"task": "Process this test input"}}'
```

## Test Scenarios

This workflow supports testing:

1. **Happy Path**: Normal task processing
2. **Error Handling**: Invalid input, guardrail violations
3. **Edge Cases**: Empty input, unicode, special characters
4. **Approval Flow**: Suspend and resume workflow
5. **Model Selection**: Dynamic model override
6. **RAG Integration**: Vector store operations
7. **Voice Processing**: Audio synthesis

## Integration with E2E Spec

The `spec/e2e/e2e_spec.cr` file contains comprehensive tests that exercise these scenarios programmatically.
