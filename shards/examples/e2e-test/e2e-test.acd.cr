# E2E Test Example Workflow
#
# This workflow demonstrates comprehensive E2E testing scenarios.
# It uses the clipproxyapi/qwen3-coder-model (configurable via COGNI_E2E_MODEL).
#
# Features demonstrated:
# - Model API configuration
# - Agent execution with schemas
# - Approval nodes
# - RAG operations
# - Voice integration
#
# Usage:
#   ./build/cogni up --port 4111 --workflows-root ./shards/examples/e2e-test

workflow "e2e-test" do
  # Use model from environment or default to qwen3-coder-model
  use model: "clipproxyapi/qwen3-coder-model"

  # Main processing agent with input/output schema validation
  agent "e2e-processor",
    input_schema: Schema::Types.object({
      "task" => Schema::Types.of(String)
    }, strict: false),
    output_schema: Schema::Types.object({
      "result" => Schema::Types.of(String)
    }, strict: false)

  # Human approval checkpoint
  approve "e2e-approval", reason: "Review E2E test output"

  # RAG integration step
  rag "e2e-rag-step", config: {
    operation: "query",
    vectorStoreName: "memory",
    indexName: "e2e-test-index",
    topK: 3
  }

  # Voice synthesis step (optional)
  voice "e2e-voice-step", config: {
    provider: "openai",
    speaker: "alloy"
  }
end
