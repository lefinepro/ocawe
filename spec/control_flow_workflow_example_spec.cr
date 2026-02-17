require "./spec_helper"
require "../shards/examples/src/control_flow_workflow_example"

describe CogniExamples::ControlFlowWorkflowExample do
  it "runs branch/parallel and other control-flow methods with schema-typed nodes" do
    workflow = CogniExamples::ControlFlowWorkflowExample.build_branch_parallel_workflow

    engine = Cogni::Workflows::Declarative::Engine.new
    engine.register(workflow)

    run = engine.create_run("control-flow-branch-parallel")
    started = run.start(input_data: {"value" => json_str("v1")})

    started.status.should eq("suspended")
    started.resume_labels.should eq(["event:deploy"])

    state = started.state.not_nil!
    state["branch"].as_s.should eq("true")
    state["left"].as_s.should eq("ok")
    state["right"].as_s.should eq("ok")
    state["then_ran"].raw.should eq(true)
    state["foreach_ran"].raw.should eq(true)
    state["dowhile_runs"].as_i.should eq(2)
    state["dountil_runs"].as_i.should eq(2)

    resumed = run.resume(resume_data: {"event_name" => json_str("deploy")})
    resumed.status.should eq("success")
    resumed.state.not_nil!["source"].as_s.should eq("example")
    resumed.state.not_nil!["event_name"].as_s.should eq("deploy")
  end
end
