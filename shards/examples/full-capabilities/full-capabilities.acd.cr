# Full capabilities example for the current .acd.cr loader.
# Demonstrates unified resource management and enhanced execution control.
# Crystal tool syntax example (requires explicit registration if used):
# tool project_healthcheck

workflow "full-capabilities" do
  # Unified resources annotation
  @[Resources(model: "cliproxyapi/qwen3-coder-plus", skill: ["full-skill"], tool: ["echo-json"])]

  agent "full-agent", input_schema: schema_ref("input"), output_schema: schema_ref("output")
  skill "full-skill", agent: "full-agent"

  agent_opencode, input_schema: Schema::Types.any(), output_schema: Schema::Types.any()
  agent_codex, model: "gpt-5", args: ["--json"], input_schema: Schema::Types.any(), output_schema: Schema::Types.any()
  agent_cliproxy, model: "qwen3-coder-plus", input_schema: Schema::Types.any(), output_schema: Schema::Types.any()

  # External tool with runtime metadata
  tool "tools/echo-json.sh", runtime: {shell: "bash"}

  voice "voice-step", config: {provider: "openai", speaker: "alloy"}
  rag "rag-step", config: {operation: "query", vectorStoreName: "memory", indexName: "full-capabilities-index", topK: 3}
  suspend "manual-approval", reason: "Confirm run output"
end
