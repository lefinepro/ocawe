struct WorkflowExampleInput
  include JSON::Serializable

  getter task : String
end

workflow "workflow-example" do
  input_type WorkflowExampleInput

  input_validate Schema::Types.object({
    "task" => Schema::Types.of(String),
  })

  agent "workflow-agent", input_schema: schema_ref("input"), output_schema: schema_ref("output")
  agent_opencode
  agent_codex
  agent_cliproxy
end
