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
      workflow = Ocawe::Workflow.create_workflow("e2e-branch", "Branch test")
      workflow
        .step(Ocawe::Workflow::WorkflowNode.new("seed", Ocawe::Workflow::NodeKind::Control) do |_ctx|
          Ocawe::Workflow::WorkflowNodeResult.continue({"selector" => json_str("A")})
        end)
        .step(Ocawe::Workflow::WorkflowNode.new("dispatch", Ocawe::Workflow::NodeKind::Control) do |ctx|
          selector = ctx.state["selector"]?.try(&.as_s?) || ""
          branch = selector == "A" ? "A" : "B"
          Ocawe::Workflow::WorkflowNodeResult.continue({"branch" => json_str(branch)})
        end)
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-branch")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["branch"].as_s.should eq("A")
    end

    it "creates workflow with unless-style conditional" do
      workflow = Ocawe::Workflow.create_workflow("control-unless", "Unless test")
      workflow
        .step(Ocawe::Workflow::WorkflowNode.new("seed", Ocawe::Workflow::NodeKind::Control) do |_ctx|
          Ocawe::Workflow::WorkflowNodeResult.continue({"skip_preprocessing" => json_bool(false)})
        end)
        .step(Ocawe::Workflow::WorkflowNode.new("unless-dispatch", Ocawe::Workflow::NodeKind::Control) do |ctx|
          skip = ctx.state["skip_preprocessing"]?.try(&.raw) == true
          payload = skip ? ({} of String => JSON::Any) : {"skipped" => json_bool(true)}
          Ocawe::Workflow::WorkflowNodeResult.continue(payload)
        end)
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("control-unless")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["skipped"].raw.should eq(true)
    end

    it "creates workflow with if/else branching" do
      workflow = Ocawe::Workflow.create_workflow("control-branch", "Branch test")
      workflow
        .step(Ocawe::Workflow::WorkflowNode.new("seed", Ocawe::Workflow::NodeKind::Control) do |_ctx|
          Ocawe::Workflow::WorkflowNodeResult.continue({"needs_translation" => json_bool(true)})
        end)
        .step(Ocawe::Workflow::WorkflowNode.new("if-else-dispatch", Ocawe::Workflow::NodeKind::Control) do |ctx|
          translated = ctx.state["needs_translation"]?.try(&.raw) == true
          action = translated ? "translated" : "passthrough"
          Ocawe::Workflow::WorkflowNodeResult.continue({"action" => json_str(action)})
        end)
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("control-branch")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["action"].as_s.should eq("translated")
    end

    it "demonstrates branch with multiple conditions" do
      workflow = Ocawe::Workflow.create_workflow("multi-branch", "Multi-branch test")
      workflow
        .step(Ocawe::Workflow::WorkflowNode.new("seed", Ocawe::Workflow::NodeKind::Control) do |_ctx|
          Ocawe::Workflow::WorkflowNodeResult.continue({"selector" => json_str("B")})
        end)
        .step(Ocawe::Workflow::WorkflowNode.new("dispatch", Ocawe::Workflow::NodeKind::Control) do |ctx|
          selector = ctx.state["selector"]?.try(&.as_s?) || ""
          path = case selector
                 when "A" then "A"
                 when "B" then "B"
                 when "C" then "C"
                 else "C"
                 end
          Ocawe::Workflow::WorkflowNodeResult.continue({"path" => json_str(path)})
        end)
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("multi-branch")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["path"].as_s.should eq("B")
    end
  end

  describe "parallel execution" do
    it "executes parallel nodes concurrently" do
      parallel_1 = Ocawe::Workflow::WorkflowNode.new("p1", Ocawe::Workflow::NodeKind::Control) do |_ctx|
        Ocawe::Workflow::WorkflowNodeResult.continue({"p1_result" => json_str("done-1")})
      end

      parallel_2 = Ocawe::Workflow::WorkflowNode.new("p2", Ocawe::Workflow::NodeKind::Control) do |_ctx|
        Ocawe::Workflow::WorkflowNodeResult.continue({"p2_result" => json_str("done-2")})
      end

      workflow = Ocawe::Workflow.create_workflow("e2e-parallel", "Parallel test")
      workflow
        .parallel([parallel_1, parallel_2])
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-parallel")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["p1_result"].as_s.should eq("done-1")
      result.state.not_nil!["p2_result"].as_s.should eq("done-2")
    end

    it "creates workflow with parallel execution" do
      validator = Ocawe::Workflow::WorkflowNode.new("validator", Ocawe::Workflow::NodeKind::Control) do |_ctx|
        Ocawe::Workflow::WorkflowNodeResult.continue({"validated" => json_bool(true)})
      end

      formatter = Ocawe::Workflow::WorkflowNode.new("formatter", Ocawe::Workflow::NodeKind::Control) do |_ctx|
        Ocawe::Workflow::WorkflowNodeResult.continue({"formatted" => json_bool(true)})
      end

      workflow = Ocawe::Workflow.create_workflow("control-parallel", "Parallel test")
      workflow
        .parallel([validator, formatter])
        .commit

      engine = Ocawe::Workflow::Engine.new
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

      workflow = Ocawe::Workflow.create_workflow("e2e-dowhile", "Loop test")
      workflow
        .step(Ocawe::Workflow::WorkflowNode.new("counter-node", Ocawe::Workflow::NodeKind::Control) do |_ctx|
          loop do
            counter += 1
            break unless counter < 3
          end
          Ocawe::Workflow::WorkflowNodeResult.continue({"count" => JSON.parse(counter.to_json)})
        end)
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-dowhile")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["count"].as_i.should eq(3)
    end

    it "executes do-until style loop in native Crystal" do
      counter = 0

      workflow = Ocawe::Workflow.create_workflow("e2e-dountil", "Until test")
      workflow
        .step(Ocawe::Workflow::WorkflowNode.new("until-node", Ocawe::Workflow::NodeKind::Control) do |_ctx|
          loop do
            counter += 1
            break if counter >= 3
          end
          Ocawe::Workflow::WorkflowNodeResult.continue({"iterations" => JSON.parse(counter.to_json)})
        end)
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-dountil")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["iterations"].as_i.should eq(3)
    end

    it "demonstrates while loop pattern" do
      counter = 0

      workflow = Ocawe::Workflow.create_workflow("while-loop", "While loop test")
      workflow
        .step(Ocawe::Workflow::WorkflowNode.new("increment", Ocawe::Workflow::NodeKind::Control) do |_ctx|
          while counter < 5
            counter += 1
          end
          Ocawe::Workflow::WorkflowNodeResult.continue({"counter" => JSON.parse(counter.to_json)})
        end)
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("while-loop")
      result = run.start
      result.status.should eq("success")
      counter.should eq(5)
    end

    it "demonstrates until loop pattern" do
      counter = 0

      workflow = Ocawe::Workflow.create_workflow("until-loop", "Until loop test")
      workflow
        .step(Ocawe::Workflow::WorkflowNode.new("increment", Ocawe::Workflow::NodeKind::Control) do |_ctx|
          until counter >= 4
            counter += 1
          end
          Ocawe::Workflow::WorkflowNodeResult.continue({"counter" => JSON.parse(counter.to_json)})
        end)
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("until-loop")
      result = run.start
      result.status.should eq("success")
      counter.should eq(4)
    end

    it "processes foreach nodes" do
      foreach_node = Ocawe::Workflow::WorkflowNode.new("process-item", Ocawe::Workflow::NodeKind::Control) do |_ctx|
        Ocawe::Workflow::WorkflowNodeResult.continue({"processed" => json_bool(true)})
      end

      workflow = Ocawe::Workflow.create_workflow("e2e-foreach", "Foreach test")
      workflow
        .foreach(foreach_node)
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-foreach")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["processed"].raw.should eq(true)
    end
  end

  describe "sequential execution" do
    it "executes sequential agent chain" do
      workflow = Ocawe::Workflow.create_workflow("control-sequential", "Sequential test")
      workflow
        .step(Ocawe::Workflow::WorkflowNode.new("preprocessor", Ocawe::Workflow::NodeKind::Control) do |_ctx|
          Ocawe::Workflow::WorkflowNodeResult.continue({"preprocessed" => json_bool(true)})
        end)
        .step(Ocawe::Workflow::WorkflowNode.new("analyzer", Ocawe::Workflow::NodeKind::Control) do |ctx|
          preprocessed = ctx.state["preprocessed"]?.try(&.raw) == true
          Ocawe::Workflow::WorkflowNodeResult.continue({"analyzed" => json_bool(preprocessed)})
        end)
        .step(Ocawe::Workflow::WorkflowNode.new("finalizer", Ocawe::Workflow::NodeKind::Control) do |ctx|
          analyzed = ctx.state["analyzed"]?.try(&.raw) == true
          Ocawe::Workflow::WorkflowNodeResult.continue({"finalized" => json_bool(analyzed)})
        end)
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("control-sequential")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["finalized"].raw.should eq(true)
    end
  end

end
