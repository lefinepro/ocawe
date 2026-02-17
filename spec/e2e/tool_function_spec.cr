require "./e2e_spec_helper"

# E2E Tests for Run and Functions
#
# Tests run and function workflow patterns:
# - Registered function execution via run
# - Function registration and chaining
# - Run context handling

describe "E2E: Run and Functions" do
  describe "run execution" do
    it "executes registered functions via run" do
      Cogni::Workflows::Declarative.register_function("e2e_test_tool") do |ctx|
        input = ctx.input_data["input"]?.try(&.as_h?) || {} of String => JSON::Any
        {
          "tool_name"  => json_any("e2e-test-tool"),
          "input_task" => json_any(input["task"]?.try(&.as_s?) || "no-task"),
          "status"     => json_any("success"),
        }
      end

      workflow = Cogni::Workflows::Declarative.create_workflow("e2e-run", "Run test")
      workflow
        .run("e2e_test_tool")
        .commit

      engine = Cogni::Workflows::Declarative::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-run")
      result = run.start(input_data: {"task" => json_str("validate-tool")})
      result.status.should eq("success")
      result.state.not_nil!["tool_name"].as_s.should eq("e2e-test-tool")
      result.state.not_nil!["input_task"].as_s.should eq("validate-tool")
    end

    it "executes run with complex input" do
      Cogni::Workflows::Declarative.register_function("complex_input_tool") do |ctx|
        input = ctx.input_data["input"]?.try(&.as_h?) || {} of String => JSON::Any
        data = input["data"]?.try(&.as_h?) || {} of String => JSON::Any
        count = data["count"]?.try(&.as_i?) || 0
        {
          "processed_count" => json_any(count * 2),
          "status"          => json_any("processed"),
        }
      end

      workflow = Cogni::Workflows::Declarative.create_workflow("complex-run-test", "Complex run test")
      workflow
        .run("complex_input_tool")
        .commit

      engine = Cogni::Workflows::Declarative::Engine.new
      engine.register(workflow)

      run = engine.create_run("complex-run-test")
      result = run.start(input_data: {
        "data" => JSON.parse({"count" => 5}.to_json),
      })
      result.status.should eq("success")
      result.state.not_nil!["processed_count"].as_i.should eq(10)
    end
  end

  describe "function chaining" do
    it "passes output from one function to the next as input envelope" do
      Cogni::Workflows::Declarative.register_function("e2e_fn_step_one") do |_ctx|
        Cogni::Workflows::Declarative::AgentResult.new(
          agent_type: "fn",
          content: "step-one-data",
        )
      end

      Cogni::Workflows::Declarative.register_function("e2e_fn_step_two") do |ctx|
        previous = ctx.input_data["input"]?.try(&.as_h?) || {} of String => JSON::Any
        received_content = previous["content"]?.try(&.as_s?) || "missing"
        Cogni::Workflows::Declarative::AgentResult.new(
          agent_type: "fn",
          content: "received:#{received_content}",
        )
      end

      workflow = Cogni::Workflows::Declarative.create_workflow("e2e-run-chain", "Function chaining")
      workflow
        .run("e2e_fn_step_one")
        .run("e2e_fn_step_two")
        .commit

      engine = Cogni::Workflows::Declarative::Engine.new
      engine.register(workflow)

      result = engine.create_run("e2e-run-chain").start
      result.status.should eq("success")
      result.state.not_nil!["content"].as_s.should eq("received:step-one-data")
    end

    it "chains multiple functions in sequence" do
      Cogni::Workflows::Declarative.register_function("chain_fn_a") do |_ctx|
        Cogni::Workflows::Declarative::AgentResult.new(
          agent_type: "fn",
          content: "A",
        )
      end

      Cogni::Workflows::Declarative.register_function("chain_fn_b") do |ctx|
        prev = ctx.input_data["input"]?.try(&.as_h?).try { |h| h["content"]?.try(&.as_s?) } || ""
        Cogni::Workflows::Declarative::AgentResult.new(
          agent_type: "fn",
          content: "#{prev}->B",
        )
      end

      Cogni::Workflows::Declarative.register_function("chain_fn_c") do |ctx|
        prev = ctx.input_data["input"]?.try(&.as_h?).try { |h| h["content"]?.try(&.as_s?) } || ""
        Cogni::Workflows::Declarative::AgentResult.new(
          agent_type: "fn",
          content: "#{prev}->C",
        )
      end

      workflow = Cogni::Workflows::Declarative.create_workflow("multi-fn-chain", "Multi function chain")
      workflow
        .run("chain_fn_a")
        .run("chain_fn_b")
        .run("chain_fn_c")
        .commit

      engine = Cogni::Workflows::Declarative::Engine.new
      engine.register(workflow)

      result = engine.create_run("multi-fn-chain").start
      result.status.should eq("success")
      result.state.not_nil!["content"].as_s.should eq("A->B->C")
    end
  end

  describe "run with workflow context" do
    it "accesses workflow state in run function" do
      Cogni::Workflows::Declarative.register_function("state_aware_tool") do |ctx|
        prev_value = ctx.state["setup_value"]?.try(&.as_s?) || "none"
        {
          "from_state" => json_any(prev_value),
          "processed"  => json_any(true),
        }
      end

      workflow = Cogni::Workflows::Declarative.create_workflow("state-run-test", "State run test")
      workflow
        .then(Cogni::Workflows::Declarative::WorkflowNode.new("setup", Cogni::Workflows::Declarative::NodeKind::Control) do |_ctx|
          Cogni::Workflows::Declarative::WorkflowNodeResult.continue({"setup_value" => json_str("initialized")})
        end)
        .run("state_aware_tool")
        .commit

      engine = Cogni::Workflows::Declarative::Engine.new
      engine.register(workflow)

      run = engine.create_run("state-run-test")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["from_state"].as_s.should eq("initialized")
    end
  end
end
