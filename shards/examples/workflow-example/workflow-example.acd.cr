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
  custom "append-note" do |ctx|
    task = ctx.state["task"]?.try(&.as_s?) || ctx.input_data["task"]?.try(&.as_s?) || ""
    Workflow::WorkflowNodeResult.continue({
      "note" => JSON.parse("Processed task: #{task}".to_json),
    })
  end
end
