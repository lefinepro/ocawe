require "./spec_helper"

describe Ocawe::Workflow::Engine do
  it "passes previous function output as input envelope for next function" do
    Ocawe::Workflow.register_function("agent_step_one") do |_ctx|
      Ocawe::Workflow::AgentResult.new(
        agent_type: "fn-agent",
        content: "step-one-output",
      )
    end

    Ocawe::Workflow.register_function("agent_step_two") do |ctx|
      previous = ctx.input_data["input"]?.try(&.as_h?) || {} of String => JSON::Any
      received = previous["content"]?.try(&.as_s?) || "missing"
      Ocawe::Workflow::AgentResult.new(
        agent_type: "fn-agent",
        content: "seen:#{received}",
      )
    end
    Ocawe::RegistryApi.node_kind("agent_step_one") do |ctx, _parameters|
      Ocawe::RegistryApi.call_function("agent_step_one", ctx)
    end
    Ocawe::RegistryApi.node_kind("agent_step_two") do |ctx, _parameters|
      Ocawe::RegistryApi.call_function("agent_step_two", ctx)
    end

    workflow = Ocawe::Workflow.create_workflow("wf-run-chain", "function chaining")
    workflow
      .step(Ocawe::NodeKind.new("agent_step_one"), id: "agent_step_one")
      .step(Ocawe::NodeKind.new("agent_step_two"), id: "agent_step_two")
      .commit

    engine = Ocawe::Workflow::Engine.new
    engine.register(workflow)

    result = engine.create_run("wf-run-chain").start(input_data: {"task" => json_str("demo")})
    result.status.should eq("success")
    result.state.not_nil!["content"].as_s.should eq("seen:step-one-output")
  end
end
