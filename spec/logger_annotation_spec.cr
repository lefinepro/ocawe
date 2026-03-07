require "./spec_helper"

describe "Logger annotation integration" do
  it "stores workflow-level logger config" do
    workflow = Cogni::Workflow.create_workflow("logger-wf", "logger")
    workflow
      .logger({
        "name" => JSON.parse("cogni".to_json),
        "level" => JSON.parse("info".to_json),
      })
      .step(Cogni::Workflow::WorkflowNode.new("noop", Cogni::Workflow::NodeKind::Control) { |_ctx|
        Cogni::Workflow::WorkflowNodeResult.continue
      })
      .commit

    workflow.default_logger.not_nil!["name"].as_s.should eq("cogni")
  end

  it "merges node logger over workflow logger" do
    workflow = Cogni::Workflow.create_workflow("logger-merge", "logger")
    workflow
      .logger({
        "name" => JSON.parse("cogni".to_json),
        "level" => JSON.parse("info".to_json),
      })
      .step(Cogni::Workflow::WorkflowNode.new("n1", Cogni::Workflow::NodeKind::Control) { |_ctx|
        Cogni::Workflow::WorkflowNodeResult.continue
      })
      .apply_logger_to_last_node({
        "level" => JSON.parse("debug".to_json),
      })
      .commit

    effective = workflow.logger_for_node("n1")
    effective.not_nil!["name"].as_s.should eq("cogni")
    effective.not_nil!["level"].as_s.should eq("debug")
  end
end
