require "./spec_helper"

class ACD::HTTP::App
  def test_wrap_nodes_in_control(
    nodes : Array(Cogni::Workflows::Declarative::WorkflowNode),
    name : String
  ) : Cogni::Workflows::Declarative::WorkflowNode
    wrap_nodes_in_control(nodes, name)
  end
end

describe "ACD::HTTP::App control wrapper" do
  it "halts wrapped if-branch execution on first non-continue result" do
    app = ACD::HTTP::App.new(0)
    executed = false

    first = Cogni::Workflows::Declarative::WorkflowNode.new("first", Cogni::Workflows::Declarative::NodeKind::Control) do |_ctx|
      Cogni::Workflows::Declarative::WorkflowNodeResult.suspend(
        {"reason" => json_str("pause")},
        resume_label: "first-stop"
      )
    end

    second = Cogni::Workflows::Declarative::WorkflowNode.new("second", Cogni::Workflows::Declarative::NodeKind::Control) do |_ctx|
      executed = true
      Cogni::Workflows::Declarative::WorkflowNodeResult.continue({"should_not_run" => json_bool(true)})
    end

    wrapped = app.test_wrap_nodes_in_control([first, second], "if-branch")
    ctx = Cogni::Workflows::Declarative::NodeContext.new(
      workflow_id: "wf",
      run_id: "run",
      node_id: "if-branch",
      input_data: {} of String => JSON::Any,
      state: {} of String => JSON::Any
    )

    result = wrapped.execute(ctx)
    result.action.should eq(Cogni::Workflows::Declarative::NodeAction::Suspend.to_s.downcase)
    result.resume_labels.should eq(["first-stop"])
    executed.should eq(false)
  end
end
