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
      workflow = Cogni::Workflows::Declarative.create_workflow("e2e-simple", "Simple workflow test")

      workflow
        .step(Cogni::Workflows::Declarative::WorkflowNode.new("step-1", Cogni::Workflows::Declarative::NodeKind::Control) do |_ctx|
          Cogni::Workflows::Declarative::WorkflowNodeResult.continue({"value" => json_str("initialized")})
        end)
        .step(Cogni::Workflows::Declarative::WorkflowNode.new("step-2", Cogni::Workflows::Declarative::NodeKind::Control) do |ctx|
          prev = ctx.state["value"]?.try(&.as_s?) || "none"
          Cogni::Workflows::Declarative::WorkflowNodeResult.continue({"value" => json_str("#{prev}:processed")})
        end)
        .commit

      engine = Cogni::Workflows::Declarative::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-simple")
      result = run.start

      result.status.should eq("success")
      result.state.not_nil!["value"].as_s.should eq("initialized:processed")
    end
  end

  describe "suspend and resume" do
    it "runs workflow with suspend and resume" do
      workflow = Cogni::Workflows::Declarative.create_workflow("e2e-approval", "Approval workflow")

      workflow
        .step(Cogni::Workflows::Declarative::WorkflowNode.new("setup", Cogni::Workflows::Declarative::NodeKind::Control) do |_ctx|
          Cogni::Workflows::Declarative::WorkflowNodeResult.continue({"prepared" => json_bool(true)})
        end)
        .suspend("human-review", reason: "Confirm data processing")
        .step(Cogni::Workflows::Declarative::WorkflowNode.new("finalize", Cogni::Workflows::Declarative::NodeKind::Control) do |_ctx|
          Cogni::Workflows::Declarative::WorkflowNodeResult.continue({"completed" => json_bool(true)})
        end)
        .commit

      engine = Cogni::Workflows::Declarative::Engine.new
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
      workflow = Cogni::Workflows::Declarative.create_workflow("e2e-timetravel", "Time travel test")

      workflow
        .step(Cogni::Workflows::Declarative::WorkflowNode.new("node-a", Cogni::Workflows::Declarative::NodeKind::Control) do |_ctx|
          Cogni::Workflows::Declarative::WorkflowNodeResult.continue({"a" => json_str("value-a")})
        end)
        .step(Cogni::Workflows::Declarative::WorkflowNode.new("node-b", Cogni::Workflows::Declarative::NodeKind::Control) do |ctx|
          Cogni::Workflows::Declarative::WorkflowNodeResult.continue({"b" => json_str("#{ctx.state["a"]?.try(&.as_s?) || "none"}-b")})
        end)
        .suspend("checkpoint")
        .step(Cogni::Workflows::Declarative::WorkflowNode.new("node-c", Cogni::Workflows::Declarative::NodeKind::Control) do |_ctx|
          Cogni::Workflows::Declarative::WorkflowNodeResult.continue({"c" => json_str("final")})
        end)
        .commit

      engine = Cogni::Workflows::Declarative::Engine.new
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
      workflow = Cogni::Workflows::Declarative.create_workflow("e2e-cancel", "Cancel test")

      workflow
        .step(Cogni::Workflows::Declarative::WorkflowNode.new("start", Cogni::Workflows::Declarative::NodeKind::Control) do |_ctx|
          Cogni::Workflows::Declarative::WorkflowNodeResult.continue({"started" => json_bool(true)})
        end)
        .suspend("wait-forever")
        .commit

      engine = Cogni::Workflows::Declarative::Engine.new
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
      workflow = Cogni::Workflows::Declarative.create_workflow("e2e-test", "E2E test workflow")
      workflow
        .use(model: "clipproxyapi/qwen3-coder-model")
        .agent("e2e-processor",
          input_schema: Cogni::Workflows::DSL::Types.object({"task" => Cogni::Workflows::DSL::Types.of(String)}, strict: false),
          output_schema: Cogni::Workflows::DSL::Types.object({"result" => Cogni::Workflows::DSL::Types.of(String)}, strict: false))
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
