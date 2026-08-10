require "./spec_helper"

private def guarded_agent_workflow(id : String)
  workflow = Ocawe::Workflow.create_workflow(id)
  agent = Ocawe::RegistryApi.build_node(
    workflow,
    "agent",
    "coder",
    model: "openai/gpt-4.1-mini",
    prompt: "Return the deterministic mock response.",
  )
  workflow.while_do("input.command.\"generate_code\"", [agent], max_iterations: 1).commit
end

describe "agent generation command tag" do
  before_each do
    ENV["COGNICORE_MOCK_LLM"] = "1"
  end

  after_each do
    ENV.delete("COGNICORE_MOCK_LLM")
  end

  it "runs the existing agent node for a true tag" do
    workflow = guarded_agent_workflow("guarded-agent-true")
    engine = Ocawe::Workflow::Engine.new
    engine.register(workflow)
    result = engine.create_run(workflow.id).start(
      input_data: {"command" => JSON.parse({"generate_code" => true}.to_json)},
    )

    result.status.should eq("success")
    state = result.state.not_nil!
    state["agent_result"].should_not be_nil
    state["last_response"].as_s.should_not be_empty
  end

  it "skips the agent for false and missing tags" do
    [
      {"command" => JSON.parse({"generate_code" => false}.to_json)},
      {"command" => JSON.parse("{}")},
    ].each_with_index do |input, index|
      workflow = guarded_agent_workflow("guarded-agent-false-#{index}")
      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)
      result = engine.create_run(workflow.id).start(input_data: input)

      result.status.should eq("success")
      result.state.not_nil!.has_key?("agent_result").should be_false
      result.state.not_nil!.has_key?("last_response").should be_false
    end
  end
end
