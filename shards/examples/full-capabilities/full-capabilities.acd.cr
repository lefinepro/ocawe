# Full capabilities example for the current .acd.cr loader.
# Crystal tool syntax example (requires explicit registration if used):
# tool project_healthcheck

workflow "full-capabilities" do
  use_model "openapi/qwen3-coder-plus"

  agent "full-agent", input_schema: schema_ref("input"), output_schema: schema_ref("output")
  skill "full-skill", agent: "full-agent"

  agent_opencode
  agent_codex
  agent_cliproxy

  # External tool with runtime metadata
  tool "tools/echo-json.sh", runtime: {shell: "bash"}

  voice "voice-step", config: {provider: "openai", speaker: "alloy"}
  rag "rag-step", config: {operation: "query", vectorStoreName: "memory", indexName: "full-capabilities-index", topK: 3}
  approve "manual-approval", reason: "Confirm run output"
end
