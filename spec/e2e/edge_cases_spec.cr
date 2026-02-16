require "./e2e_spec_helper"

describe "E2E: Edge Cases and Boundary Conditions" do
  describe "empty and minimal inputs" do
    it "handles workflow with no nodes" do
      workflow = CogniCore::Workflow.create_workflow("e2e-empty", "Empty workflow")
      workflow.commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-empty")
      result = run.start
      result.status.should eq("success")
    end

    it "handles workflow with empty input data" do
      workflow = CogniCore::Workflow.create_workflow("e2e-no-input", "No input")
      workflow
        .map("echo") { |ctx|
          has_input = !ctx.input_data.empty?
          {"has_input" => json_bool(has_input)}
        }
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-no-input")
      result = run.start
      result.status.should eq("success")
    end

    it "handles deeply nested input data" do
      workflow = CogniCore::Workflow.create_workflow("e2e-nested", "Nested input")
      workflow
        .map("extract") { |ctx|
          level3 = ctx.input_data["level1"]?
            .try(&.as_h?)
            .try(&.["level2"]?)
            .try(&.as_h?)
            .try(&.["level3"]?)
            .try(&.as_s?) || "not-found"
          {"extracted" => json_str(level3)}
        }
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      deep_input = JSON.parse({
        "level1" => {
          "level2" => {
            "level3" => "deep-value",
          },
        },
      }.to_json)

      run = engine.create_run("e2e-nested")
      result = run.start(input_data: {"level1" => deep_input["level1"]})
      result.status.should eq("success")
      result.state.not_nil!["extracted"].as_s.should eq("deep-value")
    end
  end

  describe "loop boundary conditions" do
    it "prevents infinite loops with iteration limit" do
      infinite_counter = 0

      infinite_node = CogniCore::Workflow::WorkflowNode.new("infinite", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        infinite_counter += 1
        CogniCore::Workflow::WorkflowNodeResult.continue({"count" => JSON.parse(infinite_counter.to_json)})
      end

      workflow = CogniCore::Workflow.create_workflow("e2e-infinite-guard", "Infinite guard")
      # Condition that would never be false
      workflow
        .dowhile(infinite_node, ->(_ctx : CogniCore::Workflow::NodeContext) { true })
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-infinite-guard")
      result = run.start

      # Should stop at max iterations (100)
      result.status.should eq("success")
      result.state.not_nil!["count"].as_i.should eq(100)
    end

    it "handles zero iteration loops" do
      counter = 5 # Start above threshold

      counter_node = CogniCore::Workflow::WorkflowNode.new("skip", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        counter += 1
        CogniCore::Workflow::WorkflowNodeResult.continue({"skipped" => json_bool(true)})
      end

      workflow = CogniCore::Workflow.create_workflow("e2e-zero-loop", "Zero iteration")
      # Condition already false at start
      workflow
        .dowhile(counter_node, ->(_ctx : CogniCore::Workflow::NodeContext) { counter < 3 })
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-zero-loop")
      result = run.start
      result.status.should eq("success")
      # Should execute at least once (do-while)
      counter.should eq(6)
    end
  end

  describe "parallel edge cases" do
    it "handles single node in parallel" do
      single = CogniCore::Workflow::WorkflowNode.new("only", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"only_result" => json_str("done")})
      end

      workflow = CogniCore::Workflow.create_workflow("e2e-single-parallel", "Single parallel")
      workflow
        .parallel([single])
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-single-parallel")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["only_result"].as_s.should eq("done")
    end

    it "handles parallel with one failing node" do
      success_node = CogniCore::Workflow::WorkflowNode.new("success", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"success" => json_bool(true)})
      end

      fail_node = CogniCore::Workflow::WorkflowNode.new("fail", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.fail("Intentional failure")
      end

      workflow = CogniCore::Workflow.create_workflow("e2e-parallel-fail", "Parallel with failure")
      workflow
        .parallel([success_node, fail_node])
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-parallel-fail")
      result = run.start
      result.status.should eq("failed")
      result.error.not_nil!.message.includes?("Intentional failure").should eq(true)
    end

    it "merges parallel suspend labels correctly" do
      suspend_1 = CogniCore::Workflow::WorkflowNode.new("suspend-1", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.suspend(
          {"type" => json_str("approval")},
          resume_label: "approval:1"
        )
      end

      suspend_2 = CogniCore::Workflow::WorkflowNode.new("suspend-2", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.suspend(
          {"type" => json_str("approval")},
          resume_label: "approval:2"
        )
      end

      workflow = CogniCore::Workflow.create_workflow("e2e-parallel-suspend", "Parallel suspends")
      workflow
        .parallel([suspend_1, suspend_2])
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-parallel-suspend")
      result = run.start
      result.status.should eq("suspended")
      result.resume_labels.not_nil!.includes?("approval:1").should eq(true)
      result.resume_labels.not_nil!.includes?("approval:2").should eq(true)
    end
  end

  describe "special characters and unicode" do
    it "handles unicode in input and output" do
      workflow = CogniCore::Workflow.create_workflow("e2e-unicode", "Unicode test")
      workflow
        .map("echo-unicode") { |ctx|
          text = ctx.input_data["text"]?.try(&.as_s?) || "no-text"
          {"echoed" => json_str(text)}
        }
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-unicode")
      result = run.start(input_data: {"text" => json_str("Hello 世界 🌍 مرحبا")})
      result.status.should eq("success")
      result.state.not_nil!["echoed"].as_s.should eq("Hello 世界 🌍 مرحبا")
    end

    it "handles special JSON characters" do
      workflow = CogniCore::Workflow.create_workflow("e2e-json-chars", "JSON characters")
      workflow
        .map("echo-special") { |ctx|
          text = ctx.input_data["text"]?.try(&.as_s?) || ""
          {"echoed" => json_str(text)}
        }
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-json-chars")
      result = run.start(input_data: {"text" => json_str("Line1\nLine2\tTab\"Quote")})
      result.status.should eq("success")
      result.state.not_nil!["echoed"].as_s.includes?("\n").should eq(true)
      result.state.not_nil!["echoed"].as_s.includes?("\t").should eq(true)
    end
  end
end
