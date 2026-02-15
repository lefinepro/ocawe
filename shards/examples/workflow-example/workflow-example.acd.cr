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
  agent_opencode, input_schema: Schema::Types.any(), output_schema: Schema::Types.any()
  agent_codex, input_schema: Schema::Types.any(), output_schema: Schema::Types.any()
  agent_cliproxy, input_schema: Schema::Types.any(), output_schema: Schema::Types.any()
end
