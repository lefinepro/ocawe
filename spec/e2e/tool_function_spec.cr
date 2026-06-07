require "./e2e_spec_helper"

private def map_function_to_node_kind(name : String) : Nil
  Ocawe::RegistryApi.node_kind(name) do |ctx, _parameters|
    Ocawe::RegistryApi.call_function(name, ctx)
  end
end

describe "E2E: Node Kinds and Functions" do
  describe "node kind execution" do
    it "executes registered functions via node kinds" do
      Ocawe::Workflow.register_function("e2e_test_tool") do |ctx|
        input = ctx.input_data["input"]?.try(&.as_h?) || {} of String => JSON::Any
        {
          "tool_name"  => json_any("e2e-test-tool"),
          "input_task" => json_any(input["task"]?.try(&.as_s?) || "no-task"),
          "status"     => json_any("success"),
        }
      end
      map_function_to_node_kind("e2e_test_tool")

      workflow = Ocawe::Workflow.create_workflow("e2e-run", "Run test")
      workflow
        .step(Ocawe::NodeKind.new("e2e_test_tool"), id: "e2e_test_tool")
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-run")
      result = run.start(input_data: {"task" => json_str("validate-tool")})
      result.status.should eq("success")
      result.state.not_nil!["tool_name"].as_s.should eq("e2e-test-tool")
      result.state.not_nil!["input_task"].as_s.should eq("validate-tool")
    end

    it "executes node kind with complex input" do
      Ocawe::Workflow.register_function("complex_input_tool") do |ctx|
        input = ctx.input_data["input"]?.try(&.as_h?) || {} of String => JSON::Any
        data = input["data"]?.try(&.as_h?) || {} of String => JSON::Any
        count = data["count"]?.try(&.as_i?) || 0
        {
          "processed_count" => json_any(count * 2),
          "status"          => json_any("processed"),
        }
      end
      map_function_to_node_kind("complex_input_tool")

      workflow = Ocawe::Workflow.create_workflow("complex-run-test", "Complex run test")
      workflow
        .step(Ocawe::NodeKind.new("complex_input_tool"), id: "complex_input_tool")
        .commit

      engine = Ocawe::Workflow::Engine.new
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
      Ocawe::Workflow.register_function("e2e_fn_step_one") do |_ctx|
        Ocawe::Workflow::AgentResult.new(
          agent_type: "fn",
          content: "step-one-data",
        )
      end

      Ocawe::Workflow.register_function("e2e_fn_step_two") do |ctx|
        previous = ctx.input_data["input"]?.try(&.as_h?) || {} of String => JSON::Any
        received_content = previous["content"]?.try(&.as_s?) || "missing"
        Ocawe::Workflow::AgentResult.new(
          agent_type: "fn",
          content: "received:#{received_content}",
        )
      end
      map_function_to_node_kind("e2e_fn_step_one")
      map_function_to_node_kind("e2e_fn_step_two")

      workflow = Ocawe::Workflow.create_workflow("e2e-run-chain", "Function chaining")
      workflow
        .step(Ocawe::NodeKind.new("e2e_fn_step_one"), id: "e2e_fn_step_one")
        .step(Ocawe::NodeKind.new("e2e_fn_step_two"), id: "e2e_fn_step_two")
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      result = engine.create_run("e2e-run-chain").start
      result.status.should eq("success")
      result.state.not_nil!["content"].as_s.should eq("received:step-one-data")
    end

    it "chains multiple functions in sequence" do
      Ocawe::Workflow.register_function("chain_fn_a") do |_ctx|
        Ocawe::Workflow::AgentResult.new(
          agent_type: "fn",
          content: "A",
        )
      end

      Ocawe::Workflow.register_function("chain_fn_b") do |ctx|
        prev = ctx.input_data["input"]?.try(&.as_h?).try { |h| h["content"]?.try(&.as_s?) } || ""
        Ocawe::Workflow::AgentResult.new(
          agent_type: "fn",
          content: "#{prev}->B",
        )
      end

      Ocawe::Workflow.register_function("chain_fn_c") do |ctx|
        prev = ctx.input_data["input"]?.try(&.as_h?).try { |h| h["content"]?.try(&.as_s?) } || ""
        Ocawe::Workflow::AgentResult.new(
          agent_type: "fn",
          content: "#{prev}->C",
        )
      end
      map_function_to_node_kind("chain_fn_a")
      map_function_to_node_kind("chain_fn_b")
      map_function_to_node_kind("chain_fn_c")

      workflow = Ocawe::Workflow.create_workflow("multi-fn-chain", "Multi function chain")
      workflow
        .step(Ocawe::NodeKind.new("chain_fn_a"), id: "chain_fn_a")
        .step(Ocawe::NodeKind.new("chain_fn_b"), id: "chain_fn_b")
        .step(Ocawe::NodeKind.new("chain_fn_c"), id: "chain_fn_c")
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      result = engine.create_run("multi-fn-chain").start
      result.status.should eq("success")
      result.state.not_nil!["content"].as_s.should eq("A->B->C")
    end
  end

  describe "node kind with workflow context" do
    it "accesses workflow state in node kind function" do
      Ocawe::Workflow.register_function("state_aware_tool") do |ctx|
        prev_value = ctx.state["setup_value"]?.try(&.as_s?) || "none"
        {
          "from_state" => json_any(prev_value),
          "processed"  => json_any(true),
        }
      end
      map_function_to_node_kind("state_aware_tool")

      workflow = Ocawe::Workflow.create_workflow("state-run-test", "State run test")
      workflow
        .step(Ocawe::Workflow::WorkflowNode.new("setup", Ocawe::Workflow::NodeKind::Control) do |_ctx|
          Ocawe::Workflow::WorkflowNodeResult.continue({"setup_value" => json_str("initialized")})
        end)
        .step(Ocawe::NodeKind.new("state_aware_tool"), id: "state_aware_tool")
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("state-run-test")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["from_state"].as_s.should eq("initialized")
    end
  end
end
