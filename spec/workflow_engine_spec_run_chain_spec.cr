require "./spec_helper"

describe Cogni::Workflow::Engine do
  it "passes previous function output as input envelope for next function" do
    Cogni::Workflow.register_function("agent_step_one") do |_ctx|
      Cogni::Workflow::AgentResult.new(
        agent_type: "fn-agent",
        content: "step-one-output",
      )
    end

    Cogni::Workflow.register_function("agent_step_two") do |ctx|
      previous = ctx.input_data["input"]?.try(&.as_h?) || {} of String => JSON::Any
      received = previous["content"]?.try(&.as_s?) || "missing"
      Cogni::Workflow::AgentResult.new(
        agent_type: "fn-agent",
        content: "seen:#{received}",
      )
    end
    Cogni::RegistryApi.node_kind("agent_step_one") do |ctx, _parameters|
      Cogni::RegistryApi.call_function("agent_step_one", ctx)
    end
    Cogni::RegistryApi.node_kind("agent_step_two") do |ctx, _parameters|
      Cogni::RegistryApi.call_function("agent_step_two", ctx)
    end

    workflow = Cogni::Workflow.create_workflow("wf-run-chain", "function chaining")
    workflow
      .step(Cogni::NodeKind.new("agent_step_one"), id: "agent_step_one")
      .step(Cogni::NodeKind.new("agent_step_two"), id: "agent_step_two")
      .commit

    engine = Cogni::Workflow::Engine.new
    engine.register(workflow)

    result = engine.create_run("wf-run-chain").start(input_data: {"task" => json_str("demo")})
    result.status.should eq("success")
    result.state.not_nil!["content"].as_s.should eq("seen:step-one-output")
  end
end
