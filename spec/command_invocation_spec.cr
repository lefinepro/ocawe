require "./spec_helper"

describe "bare command invocation" do
  it "resolves a registered function through the function fallback" do
    Ocawe::RegistryApi.register_function("task3_function") do |ctx|
      {
        "command_seen" => json_str(ctx.node_id),
        "carried" => ctx.state["carried"]?,
      }.compact
    end

    workflow = Ocawe::Workflow.create_workflow("task3-bare-command")
    workflow
      .step(Ocawe::NodeKind.new("task3_function"), id: "bare-function")
      .commit

    engine = Ocawe::Workflow::Engine.new
    engine.register(workflow)
    result = engine.create_run("task3-bare-command").start(
      input_data: {"carried" => json_str("prior-state")} of String => JSON::Any,
    )

    result.status.should eq("success")
    state = result.state.not_nil!
    state["command_seen"].as_s.should eq("bare-function")
    state["carried"].as_s.should eq("prior-state")
  end

  it "keeps unknown bare names as explicit workflow failures" do
    workflow = Ocawe::Workflow.create_workflow("task3-unknown-command")
    workflow
      .step(Ocawe::NodeKind.new("task3_missing_command"), id: "unknown-command")
      .commit

    engine = Ocawe::Workflow::Engine.new
    engine.register(workflow)
    result = engine.create_run("task3-unknown-command").start

    result.status.should eq("failed")
    result.error.not_nil!.message.should contain("unknown node kind")
  end
end
