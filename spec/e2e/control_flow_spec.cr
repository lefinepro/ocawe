require "./e2e_spec_helper"

# E2E Tests for Control Flow
#
# Tests control flow patterns with supported workflow APIs:
# - Sequential control nodes
# - Parallel execution
# - Native Crystal conditions/loops inside nodes
# - Events (wait_for_event, send_event)
# - Sleep nodes

describe "E2E: Control Flow" do
  describe "branching" do
    it "executes branch-like conditions correctly" do
      workflow = CogniCore::Workflow.create_workflow("e2e-branch", "Branch test")
      workflow
        .then(CogniCore::Workflow::WorkflowNode.new("seed", CogniCore::Workflow::NodeKind::Control) do |_ctx|
          CogniCore::Workflow::WorkflowNodeResult.continue({"selector" => json_str("A")})
        end)
        .then(CogniCore::Workflow::WorkflowNode.new("dispatch", CogniCore::Workflow::NodeKind::Control) do |ctx|
          selector = ctx.state["selector"]?.try(&.as_s?) || ""
          branch = selector == "A" ? "A" : "B"
          CogniCore::Workflow::WorkflowNodeResult.continue({"branch" => json_str(branch)})
        end)
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-branch")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["branch"].as_s.should eq("A")
    end

    it "creates workflow with unless-style conditional" do
      workflow = CogniCore::Workflow.create_workflow("control-unless", "Unless test")
      workflow
        .then(CogniCore::Workflow::WorkflowNode.new("seed", CogniCore::Workflow::NodeKind::Control) do |_ctx|
          CogniCore::Workflow::WorkflowNodeResult.continue({"skip_preprocessing" => json_bool(false)})
        end)
        .then(CogniCore::Workflow::WorkflowNode.new("unless-dispatch", CogniCore::Workflow::NodeKind::Control) do |ctx|
          skip = ctx.state["skip_preprocessing"]?.try(&.raw) == true
          payload = skip ? ({} of String => JSON::Any) : {"skipped" => json_bool(true)}
          CogniCore::Workflow::WorkflowNodeResult.continue(payload)
        end)
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("control-unless")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["skipped"].raw.should eq(true)
    end

    it "creates workflow with if/else branching" do
      workflow = CogniCore::Workflow.create_workflow("control-branch", "Branch test")
      workflow
        .then(CogniCore::Workflow::WorkflowNode.new("seed", CogniCore::Workflow::NodeKind::Control) do |_ctx|
          CogniCore::Workflow::WorkflowNodeResult.continue({"needs_translation" => json_bool(true)})
        end)
        .then(CogniCore::Workflow::WorkflowNode.new("if-else-dispatch", CogniCore::Workflow::NodeKind::Control) do |ctx|
          translated = ctx.state["needs_translation"]?.try(&.raw) == true
          action = translated ? "translated" : "passthrough"
          CogniCore::Workflow::WorkflowNodeResult.continue({"action" => json_str(action)})
        end)
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("control-branch")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["action"].as_s.should eq("translated")
    end

    it "demonstrates branch with multiple conditions" do
      workflow = CogniCore::Workflow.create_workflow("multi-branch", "Multi-branch test")
      workflow
        .then(CogniCore::Workflow::WorkflowNode.new("seed", CogniCore::Workflow::NodeKind::Control) do |_ctx|
          CogniCore::Workflow::WorkflowNodeResult.continue({"selector" => json_str("B")})
        end)
        .then(CogniCore::Workflow::WorkflowNode.new("dispatch", CogniCore::Workflow::NodeKind::Control) do |ctx|
          selector = ctx.state["selector"]?.try(&.as_s?) || ""
          path = case selector
                 when "A" then "A"
                 when "B" then "B"
                 when "C" then "C"
                 else "C"
                 end
          CogniCore::Workflow::WorkflowNodeResult.continue({"path" => json_str(path)})
        end)
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
    it "executes do-while style loop in native Crystal" do
      counter = 0

      workflow = CogniCore::Workflow.create_workflow("e2e-dowhile", "Loop test")
      workflow
        .then(CogniCore::Workflow::WorkflowNode.new("counter-node", CogniCore::Workflow::NodeKind::Control) do |_ctx|
          loop do
            counter += 1
            break unless counter < 3
          end
          CogniCore::Workflow::WorkflowNodeResult.continue({"count" => JSON.parse(counter.to_json)})
        end)
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-dowhile")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["count"].as_i.should eq(3)
    end

    it "executes do-until style loop in native Crystal" do
      counter = 0

      workflow = CogniCore::Workflow.create_workflow("e2e-dountil", "Until test")
      workflow
        .then(CogniCore::Workflow::WorkflowNode.new("until-node", CogniCore::Workflow::NodeKind::Control) do |_ctx|
          loop do
            counter += 1
            break if counter >= 3
          end
          CogniCore::Workflow::WorkflowNodeResult.continue({"iterations" => JSON.parse(counter.to_json)})
        end)
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

      workflow = CogniCore::Workflow.create_workflow("while-loop", "While loop test")
      workflow
        .then(CogniCore::Workflow::WorkflowNode.new("increment", CogniCore::Workflow::NodeKind::Control) do |_ctx|
          while counter < 5
            counter += 1
          end
          CogniCore::Workflow::WorkflowNodeResult.continue({"counter" => JSON.parse(counter.to_json)})
        end)
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

      workflow = CogniCore::Workflow.create_workflow("until-loop", "Until loop test")
      workflow
        .then(CogniCore::Workflow::WorkflowNode.new("increment", CogniCore::Workflow::NodeKind::Control) do |_ctx|
          until counter >= 4
            counter += 1
          end
          CogniCore::Workflow::WorkflowNodeResult.continue({"counter" => JSON.parse(counter.to_json)})
        end)
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
        .then(CogniCore::Workflow::WorkflowNode.new("preprocessor", CogniCore::Workflow::NodeKind::Control) do |_ctx|
          CogniCore::Workflow::WorkflowNodeResult.continue({"preprocessed" => json_bool(true)})
        end)
        .then(CogniCore::Workflow::WorkflowNode.new("analyzer", CogniCore::Workflow::NodeKind::Control) do |ctx|
          preprocessed = ctx.state["preprocessed"]?.try(&.raw) == true
          CogniCore::Workflow::WorkflowNodeResult.continue({"analyzed" => json_bool(preprocessed)})
        end)
        .then(CogniCore::Workflow::WorkflowNode.new("finalizer", CogniCore::Workflow::NodeKind::Control) do |ctx|
          analyzed = ctx.state["analyzed"]?.try(&.raw) == true
          CogniCore::Workflow::WorkflowNodeResult.continue({"finalized" => json_bool(analyzed)})
        end)
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
        .then(CogniCore::Workflow::WorkflowNode.new("before", CogniCore::Workflow::NodeKind::Control) do |_ctx|
          CogniCore::Workflow::WorkflowNodeResult.continue({"before" => json_bool(true)})
        end)
        .sleep(10) # 10ms sleep
        .then(CogniCore::Workflow::WorkflowNode.new("after", CogniCore::Workflow::NodeKind::Control) do |_ctx|
          CogniCore::Workflow::WorkflowNodeResult.continue({"after" => json_bool(true)})
        end)
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
        .then(CogniCore::Workflow::WorkflowNode.new("init", CogniCore::Workflow::NodeKind::Control) do |_ctx|
          CogniCore::Workflow::WorkflowNodeResult.continue({"initialized" => json_bool(true)})
        end)
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
