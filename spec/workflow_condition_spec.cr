require "./spec_helper"

private def condition_probe_workflow(id : String, condition : String)
  probe = Ocawe::Workflow::WorkflowNode.new("condition-probe", Ocawe::Workflow::NodeKind::Control) do |_ctx|
    Ocawe::Workflow::WorkflowNodeResult.continue({"ran" => json_bool(true)})
  end

  Ocawe::Workflow.create_workflow(id)
    .while_do(condition, [probe], max_iterations: 1)
    .commit
end

private def run_condition_probe(workflow, input : Ocawe::Workflow::AnyHash)
  engine = Ocawe::Workflow::Engine.new
  engine.register(workflow)
  engine.create_run(workflow.id).start(input_data: input)
end

describe "workflow condition paths" do
  it "accepts a quoted segment after a dot and matches bracket lookup" do
    dotted = condition_probe_workflow("condition-dotted", "input.command.\"generate_code\"")
    bracketed = condition_probe_workflow("condition-bracketed", "input.command[\"generate_code\"]")
    input = {"command" => JSON.parse({"generate_code" => true}.to_json)}

    run_condition_probe(dotted, input).state.not_nil!["ran"].as_bool.should be_true
    run_condition_probe(bracketed, input).state.not_nil!["ran"].as_bool.should be_true
  end

  it "treats missing, null, false, empty strings, arrays, and objects as false" do
    values = [
      {} of String => JSON::Any,
      {"generate_code" => JSON.parse("null")},
      {"generate_code" => json_bool(false)},
      {"generate_code" => json_str("")},
      {"generate_code" => JSON.parse("[]")},
      {"generate_code" => JSON.parse("{}")},
    ]

    values.each_with_index do |command, index|
      workflow = condition_probe_workflow("condition-false-#{index}", "input.command.\"generate_code\"")
      result = run_condition_probe(workflow, {"command" => JSON.parse(command.to_json)})
      result.state.not_nil!.has_key?("ran").should be_false
    end
  end

  it "never dispatches a command from the tag value" do
    workflow = condition_probe_workflow("condition-no-dispatch", "input.command.\"generate_code\"")
    result = run_condition_probe(workflow, {
      "command" => JSON.parse({"generate_code" => "task3_missing_command"}.to_json),
    })

    result.status.should eq("success")
    result.state.not_nil!["ran"].as_bool.should be_true
  end
end
