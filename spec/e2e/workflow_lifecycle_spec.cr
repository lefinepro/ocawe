require "./e2e_spec_helper"

# E2E Tests for Workflow Lifecycle
#
# Tests workflow lifecycle operations:
# - Create and run simple workflows
# - Suspend and resume workflows
# - Time travel (replay from specific node)
# - Cancel workflows

describe "E2E: Workflow Lifecycle" do
  describe "basic workflow operations" do
    it "creates and runs a simple workflow with control nodes" do
      workflow = CogniCore::Workflow.create_workflow("e2e-simple", "Simple workflow test")

      workflow
        .then(CogniCore::Workflow::WorkflowNode.new("step-1", CogniCore::Workflow::NodeKind::Control) do |_ctx|
          CogniCore::Workflow::WorkflowNodeResult.continue({"value" => json_str("initialized")})
        end)
        .then(CogniCore::Workflow::WorkflowNode.new("step-2", CogniCore::Workflow::NodeKind::Control) do |ctx|
          prev = ctx.state["value"]?.try(&.as_s?) || "none"
          CogniCore::Workflow::WorkflowNodeResult.continue({"value" => json_str("#{prev}:processed")})
        end)
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-simple")
      result = run.start

      result.status.should eq("success")
      result.state.not_nil!["value"].as_s.should eq("initialized:processed")
    end
  end

  describe "suspend and resume" do
    it "runs workflow with suspend and resume" do
      workflow = CogniCore::Workflow.create_workflow("e2e-approval", "Approval workflow")

      workflow
        .then(CogniCore::Workflow::WorkflowNode.new("setup", CogniCore::Workflow::NodeKind::Control) do |_ctx|
          CogniCore::Workflow::WorkflowNodeResult.continue({"prepared" => json_bool(true)})
        end)
        .suspend("human-review", reason: "Confirm data processing")
        .then(CogniCore::Workflow::WorkflowNode.new("finalize", CogniCore::Workflow::NodeKind::Control) do |_ctx|
          CogniCore::Workflow::WorkflowNodeResult.continue({"completed" => json_bool(true)})
        end)
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-approval")

      # Start workflow - should suspend at approval
      started = run.start
      started.status.should eq("suspended")
      started.resume_labels.should eq(["human-review"])
      started.state.not_nil!["prepared"].raw.should eq(true)

      # Resume with approval
      resumed = run.resume(resume_data: {
        "approved" => json_bool(true),
        "comment"  => json_str("Approved by reviewer"),
      })
      resumed.status.should eq("success")
      resumed.state.not_nil!["completed"].raw.should eq(true)
      resumed.state.not_nil!["resume_data"].as_h["approved"].raw.should eq(true)
    end

  end

  describe "time travel" do
    it "runs workflow with time travel to replay from specific node" do
      workflow = CogniCore::Workflow.create_workflow("e2e-timetravel", "Time travel test")

      workflow
        .then(CogniCore::Workflow::WorkflowNode.new("node-a", CogniCore::Workflow::NodeKind::Control) do |_ctx|
          CogniCore::Workflow::WorkflowNodeResult.continue({"a" => json_str("value-a")})
        end)
        .then(CogniCore::Workflow::WorkflowNode.new("node-b", CogniCore::Workflow::NodeKind::Control) do |ctx|
          CogniCore::Workflow::WorkflowNodeResult.continue({"b" => json_str("#{ctx.state["a"]?.try(&.as_s?) || "none"}-b")})
        end)
        .suspend("checkpoint")
        .then(CogniCore::Workflow::WorkflowNode.new("node-c", CogniCore::Workflow::NodeKind::Control) do |_ctx|
          CogniCore::Workflow::WorkflowNodeResult.continue({"c" => json_str("final")})
        end)
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-timetravel")
      started = run.start
      started.status.should eq("suspended")
      started.state.not_nil!["b"].as_s.should eq("value-a-b")

      # Time travel back to node-a with new input
      timed = run.time_travel(node: "node-a", input_data: {"replay" => json_bool(true)})
      timed.status.should eq("suspended")
    end
  end

  describe "cancel" do
    it "runs workflow with cancel operation" do
      workflow = CogniCore::Workflow.create_workflow("e2e-cancel", "Cancel test")

      workflow
        .then(CogniCore::Workflow::WorkflowNode.new("start", CogniCore::Workflow::NodeKind::Control) do |_ctx|
          CogniCore::Workflow::WorkflowNodeResult.continue({"started" => json_bool(true)})
        end)
        .suspend("wait-forever")
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-cancel")
      started = run.start
      started.status.should eq("suspended")

      cancelled = run.cancel
      cancelled.status.should eq("cancelled")
    end
  end

  describe "e2e-test example workflow" do
    it "creates workflow with agent, approval, rag, and voice nodes" do
      # Simulates e2e-test workflow from shards/examples/e2e-test
      workflow = CogniCore::Workflow.create_workflow("e2e-test", "E2E test workflow")
      workflow
        .use(model: "clipproxyapi/qwen3-coder-model")
        .agent("e2e-processor",
          input_schema: CogniCore::Schema::Types.object({"task" => CogniCore::Schema::Types.of(String)}, strict: false),
          output_schema: CogniCore::Schema::Types.object({"result" => CogniCore::Schema::Types.of(String)}, strict: false))
        .suspend("e2e-approval", reason: "Review E2E test output")
        .rag("e2e-rag-step", config: {
          "operation"       => json_str("query"),
          "vectorStoreName" => json_str("memory"),
          "indexName"       => json_str("e2e-test-index"),
          "topK"            => JSON.parse(3.to_json),
        })
        .voice("e2e-voice-step", config: {
          "provider" => json_str("openai"),
          "speaker"  => json_str("alloy"),
        })
        .commit

      workflow.default_model.should eq("clipproxyapi/qwen3-coder-model")
      workflow.nodes.size.should eq(4)
      workflow.nodes[0].id.should eq("e2e-processor")
      workflow.nodes[1].id.should eq("e2e-approval")
      workflow.nodes[2].id.should eq("e2e-rag-step")
      workflow.nodes[3].id.should eq("e2e-voice-step")
    end
  end
end
