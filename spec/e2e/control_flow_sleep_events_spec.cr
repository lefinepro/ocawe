require "./e2e_spec_helper"

describe "E2E: Control Flow" do
  describe "sleep and events" do
    it "handles sleep nodes" do
      workflow = Ocawe::Workflow.create_workflow("e2e-sleep", "Sleep test")
      workflow
        .step(Ocawe::Workflow::WorkflowNode.new("before", Ocawe::Workflow::NodeKind::Control) do |_ctx|
          Ocawe::Workflow::WorkflowNodeResult.continue({"before" => json_bool(true)})
        end)
        .sleep(10) # 10ms sleep
        .step(Ocawe::Workflow::WorkflowNode.new("after", Ocawe::Workflow::NodeKind::Control) do |_ctx|
          Ocawe::Workflow::WorkflowNodeResult.continue({"after" => json_bool(true)})
        end)
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-sleep")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["after"].raw.should eq(true)
    end

    it "handles wait_for_event and send_event" do
      workflow = Ocawe::Workflow.create_workflow("e2e-events", "Events test")
      workflow
        .step(Ocawe::Workflow::WorkflowNode.new("init", Ocawe::Workflow::NodeKind::Control) do |_ctx|
          Ocawe::Workflow::WorkflowNodeResult.continue({"initialized" => json_bool(true)})
        end)
        .wait_for_event("data-ready", "event:data-ready")
        .send_event("data-ready", {"source" => json_str("test")})
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-events")
      started = run.start
      started.status.should eq("suspended")
      started.resume_labels.should eq(["event:data-ready"])

      resumed = run.resume(resume_data: {"event_name" => json_str("data-ready")})
      resumed.status.should eq("success")
      resumed.state.not_nil!["source"].as_s.should eq("test")
    end
  end
end
