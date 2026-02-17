require "./e2e_spec_helper"

# E2E Tests for Tools and Functions
#
# Tests tool and function workflow patterns:
# - Crystal tool execution
# - Function registration and chaining
# - Tool error handling

describe "E2E: Tools and Functions" do
  describe "tool execution" do
    it "executes crystal tool functions" do
      CogniCore::Workflow.register_tool("e2e_test_tool") do |ctx|
        {
          "tool_name"  => json_any("e2e-test-tool"),
          "input_task" => json_any(ctx.input_data["task"]?.try(&.as_s?) || "no-task"),
          "status"     => json_any("success"),
        }
      end

      workflow = CogniCore::Workflow.create_workflow("e2e-tool", "Tool test")
      workflow
        .tool("e2e_test_tool")
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-tool")
      result = run.start(input_data: {"task" => json_str("validate-tool")})
      result.status.should eq("success")
      result.state.not_nil!["tool_name"].as_s.should eq("e2e-test-tool")
      result.state.not_nil!["input_task"].as_s.should eq("validate-tool")
    end

    it "executes tool with complex input" do
      CogniCore::Workflow.register_tool("complex_input_tool") do |ctx|
        data = ctx.input_data["data"]?.try(&.as_h?) || {} of String => JSON::Any
        count = data["count"]?.try(&.as_i?) || 0
        {
          "processed_count" => json_any(count * 2),
          "status"          => json_any("processed"),
        }
      end

      workflow = CogniCore::Workflow.create_workflow("complex-tool-test", "Complex tool test")
      workflow
        .tool("complex_input_tool")
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("complex-tool-test")
      result = run.start(input_data: {
        "data" => JSON.parse({"count" => 5}.to_json),
      })
      result.status.should eq("success")
      result.state.not_nil!["processed_count"].as_i.should eq(10)
    end
  end

  describe "function chaining" do
    it "passes output from one function to the next as input envelope" do
      CogniCore::Workflow.register_function("e2e_fn_step_one") do |_ctx|
        CogniCore::Workflow::AgentResult.new(
          agent_type: "fn",
          content: "step-one-data",
        )
      end

      CogniCore::Workflow.register_function("e2e_fn_step_two") do |ctx|
        previous = ctx.input_data["input"]?.try(&.as_h?) || {} of String => JSON::Any
        received_content = previous["content"]?.try(&.as_s?) || "missing"
        CogniCore::Workflow::AgentResult.new(
          agent_type: "fn",
          content: "received:#{received_content}",
        )
      end

      workflow = CogniCore::Workflow.create_workflow("e2e-fn-chain", "Function chaining")
      workflow
        .fn("e2e_fn_step_one")
        .fn("e2e_fn_step_two")
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      result = engine.create_run("e2e-fn-chain").start
      result.status.should eq("success")
      result.state.not_nil!["content"].as_s.should eq("received:step-one-data")
    end

    it "chains multiple functions in sequence" do
      CogniCore::Workflow.register_function("chain_fn_a") do |_ctx|
        CogniCore::Workflow::AgentResult.new(
          agent_type: "fn",
          content: "A",
        )
      end

      CogniCore::Workflow.register_function("chain_fn_b") do |ctx|
        prev = ctx.input_data["input"]?.try(&.as_h?).try { |h| h["content"]?.try(&.as_s?) } || ""
        CogniCore::Workflow::AgentResult.new(
          agent_type: "fn",
          content: "#{prev}->B",
        )
      end

      CogniCore::Workflow.register_function("chain_fn_c") do |ctx|
        prev = ctx.input_data["input"]?.try(&.as_h?).try { |h| h["content"]?.try(&.as_s?) } || ""
        CogniCore::Workflow::AgentResult.new(
          agent_type: "fn",
          content: "#{prev}->C",
        )
      end

      workflow = CogniCore::Workflow.create_workflow("multi-fn-chain", "Multi function chain")
      workflow
        .fn("chain_fn_a")
        .fn("chain_fn_b")
        .fn("chain_fn_c")
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      result = engine.create_run("multi-fn-chain").start
      result.status.should eq("success")
      result.state.not_nil!["content"].as_s.should eq("A->B->C")
    end
  end

  describe "tool with workflow context" do
    it "accesses workflow state in tool" do
      CogniCore::Workflow.register_tool("state_aware_tool") do |ctx|
        prev_value = ctx.state["setup_value"]?.try(&.as_s?) || "none"
        {
          "from_state" => json_any(prev_value),
          "processed"  => json_any(true),
        }
      end

      workflow = CogniCore::Workflow.create_workflow("state-tool-test", "State tool test")
      workflow
        .then(CogniCore::Workflow::WorkflowNode.new("setup", CogniCore::Workflow::NodeKind::Control) do |_ctx|
          CogniCore::Workflow::WorkflowNodeResult.continue({"setup_value" => json_str("initialized")})
        end)
        .tool("state_aware_tool")
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("state-tool-test")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["from_state"].as_s.should eq("initialized")
    end
  end
end
