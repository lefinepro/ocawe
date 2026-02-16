require "./e2e_spec_helper"

# E2E Tests for Control Flow
#
# Tests control flow patterns:
# - Branching (if/else, unless)
# - Parallel execution
# - Loops (while, until, dowhile, dountil, foreach)
# - Events (wait_for_event, send_event)
# - Sleep nodes

describe "E2E: Control Flow" do
  describe "branching" do
    it "executes branch conditions correctly" do
      branch_a = CogniCore::Workflow::WorkflowNode.new("branch-a", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"branch" => json_str("A")})
      end

      branch_b = CogniCore::Workflow::WorkflowNode.new("branch-b", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"branch" => json_str("B")})
      end

      workflow = CogniCore::Workflow.create_workflow("e2e-branch", "Branch test")
      workflow
        .map("seed") { |_ctx| {"selector" => json_str("A")} }
        .branch([
          {->(ctx : CogniCore::Workflow::NodeContext) { ctx.state["selector"]?.try(&.as_s?) == "A" }, branch_a},
          {->(ctx : CogniCore::Workflow::NodeContext) { ctx.state["selector"]?.try(&.as_s?) == "B" }, branch_b},
        ] of Tuple(CogniCore::Workflow::BranchCondition, CogniCore::Workflow::WorkflowNode), otherwise_node: branch_b)
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-branch")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["branch"].as_s.should eq("A")
    end

    it "creates workflow with unless conditional" do
      # Simulates control-flow unless branch
      skip_node = CogniCore::Workflow::WorkflowNode.new("skipped", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"skipped" => json_bool(true)})
      end

      workflow = CogniCore::Workflow.create_workflow("control-unless", "Unless test")
      workflow
        .map("seed") { |_ctx| {"skip_preprocessing" => json_bool(false)} }
        .unless_branch(
          ->(ctx : CogniCore::Workflow::NodeContext) { ctx.state["skip_preprocessing"]?.try(&.raw) == true },
          skip_node)
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("control-unless")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["skipped"].raw.should eq(true)
    end

    it "creates workflow with if/else branching" do
      # Simulates: if input.needs_translation then translator else passthrough
      translator = CogniCore::Workflow::WorkflowNode.new("translator", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"action" => json_str("translated")})
      end

      passthrough = CogniCore::Workflow::WorkflowNode.new("passthrough", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"action" => json_str("passthrough")})
      end

      workflow = CogniCore::Workflow.create_workflow("control-branch", "Branch test")
      workflow
        .map("seed") { |_ctx| {"needs_translation" => json_bool(true)} }
        .branch([
          {->(ctx : CogniCore::Workflow::NodeContext) { ctx.state["needs_translation"]?.try(&.raw) == true }, translator},
        ] of Tuple(CogniCore::Workflow::BranchCondition, CogniCore::Workflow::WorkflowNode), otherwise_node: passthrough)
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("control-branch")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["action"].as_s.should eq("translated")
    end

    it "demonstrates branch with multiple conditions" do
      # Test branch with multiple conditions
      branch_a = CogniCore::Workflow::WorkflowNode.new("path-a", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"path" => json_str("A")})
      end
      branch_b = CogniCore::Workflow::WorkflowNode.new("path-b", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"path" => json_str("B")})
      end
      branch_c = CogniCore::Workflow::WorkflowNode.new("path-c", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"path" => json_str("C")})
      end

      workflow = CogniCore::Workflow.create_workflow("multi-branch", "Multi-branch test")
      workflow
        .map("seed") { |_ctx| {"selector" => json_str("B")} }
        .branch([
          {->(ctx : CogniCore::Workflow::NodeContext) { ctx.state["selector"]?.try(&.as_s?) == "A" }, branch_a},
          {->(ctx : CogniCore::Workflow::NodeContext) { ctx.state["selector"]?.try(&.as_s?) == "B" }, branch_b},
          {->(ctx : CogniCore::Workflow::NodeContext) { ctx.state["selector"]?.try(&.as_s?) == "C" }, branch_c},
        ] of Tuple(CogniCore::Workflow::BranchCondition, CogniCore::Workflow::WorkflowNode))
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("multi-branch")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["path"].as_s.should eq("B")
    end
  end

  describe "parallel execution" do
    it "executes parallel nodes concurrently" do
      parallel_1 = CogniCore::Workflow::WorkflowNode.new("p1", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"p1_result" => json_str("done-1")})
      end

      parallel_2 = CogniCore::Workflow::WorkflowNode.new("p2", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"p2_result" => json_str("done-2")})
      end

      workflow = CogniCore::Workflow.create_workflow("e2e-parallel", "Parallel test")
      workflow
        .parallel([parallel_1, parallel_2])
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-parallel")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["p1_result"].as_s.should eq("done-1")
      result.state.not_nil!["p2_result"].as_s.should eq("done-2")
    end

    it "creates workflow with parallel execution" do
      # Simulates: parallel do agent "validator"; agent "formatter" end
      validator = CogniCore::Workflow::WorkflowNode.new("validator", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"validated" => json_bool(true)})
      end

      formatter = CogniCore::Workflow::WorkflowNode.new("formatter", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"formatted" => json_bool(true)})
      end

      workflow = CogniCore::Workflow.create_workflow("control-parallel", "Parallel test")
      workflow
        .parallel([validator, formatter])
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("control-parallel")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["validated"].raw.should eq(true)
      result.state.not_nil!["formatted"].raw.should eq(true)
    end
  end

  describe "loops" do
    it "executes dowhile loop until condition fails" do
      counter = 0

      do_node = CogniCore::Workflow::WorkflowNode.new("counter-node", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        counter += 1
        CogniCore::Workflow::WorkflowNodeResult.continue({"count" => JSON.parse(counter.to_json)})
      end

      workflow = CogniCore::Workflow.create_workflow("e2e-dowhile", "Loop test")
      workflow
        .dowhile(do_node, ->(_ctx : CogniCore::Workflow::NodeContext) { counter < 3 })
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-dowhile")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["count"].as_i.should eq(3)
    end

    it "executes dountil loop until condition becomes true" do
      counter = 0

      until_node = CogniCore::Workflow::WorkflowNode.new("until-node", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        counter += 1
        CogniCore::Workflow::WorkflowNodeResult.continue({"iterations" => JSON.parse(counter.to_json)})
      end

      workflow = CogniCore::Workflow.create_workflow("e2e-dountil", "Until test")
      workflow
        .dountil(until_node, ->(_ctx : CogniCore::Workflow::NodeContext) { counter >= 3 })
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-dountil")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["iterations"].as_i.should eq(3)
    end

    it "demonstrates while loop pattern" do
      counter = 0
      loop_node = CogniCore::Workflow::WorkflowNode.new("increment", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        counter += 1
        CogniCore::Workflow::WorkflowNodeResult.continue({"counter" => JSON.parse(counter.to_json)})
      end

      workflow = CogniCore::Workflow.create_workflow("while-loop", "While loop test")
      workflow
        .while_loop(loop_node, ->(_ctx : CogniCore::Workflow::NodeContext) { counter < 5 })
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("while-loop")
      result = run.start
      result.status.should eq("success")
      counter.should eq(5)
    end

    it "demonstrates until loop pattern" do
      counter = 0
      loop_node = CogniCore::Workflow::WorkflowNode.new("increment", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        counter += 1
        CogniCore::Workflow::WorkflowNodeResult.continue({"counter" => JSON.parse(counter.to_json)})
      end

      workflow = CogniCore::Workflow.create_workflow("until-loop", "Until loop test")
      workflow
        .until_loop(loop_node, ->(_ctx : CogniCore::Workflow::NodeContext) { counter >= 4 })
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("until-loop")
      result = run.start
      result.status.should eq("success")
      counter.should eq(4)
    end

    it "processes foreach nodes" do
      foreach_node = CogniCore::Workflow::WorkflowNode.new("process-item", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"processed" => json_bool(true)})
      end

      workflow = CogniCore::Workflow.create_workflow("e2e-foreach", "Foreach test")
      workflow
        .foreach(foreach_node)
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-foreach")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["processed"].raw.should eq(true)
    end
  end

  describe "sequential execution" do
    it "executes sequential agent chain" do
      workflow = CogniCore::Workflow.create_workflow("control-sequential", "Sequential test")
      workflow
        .map("preprocessor") { |_ctx| {"preprocessed" => json_bool(true)} }
        .map("analyzer") { |ctx|
          preprocessed = ctx.state["preprocessed"]?.try(&.raw) == true
          {"analyzed" => json_bool(preprocessed)}
        }
        .map("finalizer") { |ctx|
          analyzed = ctx.state["analyzed"]?.try(&.raw) == true
          {"finalized" => json_bool(analyzed)}
        }
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("control-sequential")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["finalized"].raw.should eq(true)
    end
  end

  describe "sleep and events" do
    it "handles sleep nodes" do
      workflow = CogniCore::Workflow.create_workflow("e2e-sleep", "Sleep test")
      workflow
        .map("before") { |_ctx| {"before" => json_bool(true)} }
        .sleep(10) # 10ms sleep
        .map("after") { |_ctx| {"after" => json_bool(true)} }
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-sleep")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["after"].raw.should eq(true)
    end

    it "handles wait_for_event and send_event" do
      workflow = CogniCore::Workflow.create_workflow("e2e-events", "Events test")
      workflow
        .map("init") { |_ctx| {"initialized" => json_bool(true)} }
        .wait_for_event("data-ready", "event:data-ready")
        .send_event("data-ready", {"source" => json_str("test")})
        .commit

      engine = CogniCore::Workflow::Engine.new
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
