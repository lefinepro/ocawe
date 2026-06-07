require "./e2e_spec_helper"

describe "E2E: Data Persistence and State" do
  describe "state accumulation" do
    it "accumulates state across multiple nodes" do
      workflow = Ocawe::Workflow.create_workflow("e2e-state-accum", "State accumulation")
      workflow
        .step(Ocawe::Workflow::WorkflowNode.new("step-1", Ocawe::Workflow::NodeKind::Control) do |_ctx|
          Ocawe::Workflow::WorkflowNodeResult.continue({"value_1" => json_str("one")})
        end)
        .step(Ocawe::Workflow::WorkflowNode.new("step-2", Ocawe::Workflow::NodeKind::Control) do |ctx|
          prev = ctx.state["value_1"]?.try(&.as_s?) || "none"
          Ocawe::Workflow::WorkflowNodeResult.continue({"value_2" => json_str("two:#{prev}")})
        end)
        .step(Ocawe::Workflow::WorkflowNode.new("step-3", Ocawe::Workflow::NodeKind::Control) do |ctx|
          v1 = ctx.state["value_1"]?.try(&.as_s?) || "none"
          v2 = ctx.state["value_2"]?.try(&.as_s?) || "none"
          Ocawe::Workflow::WorkflowNodeResult.continue({"final" => json_str("#{v1}|#{v2}")})
        end)
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-state-accum")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["value_1"].as_s.should eq("one")
      result.state.not_nil!["value_2"].as_s.should eq("two:one")
      result.state.not_nil!["final"].as_s.should eq("one|two:one")
    end
  end

  describe "node results access" do
    it "provides access to previous node results" do
      workflow = Ocawe::Workflow.create_workflow("e2e-node-results", "Node results")
      workflow
        .step(Ocawe::Workflow::WorkflowNode.new("producer", Ocawe::Workflow::NodeKind::Control) do |_ctx|
          Ocawe::Workflow::WorkflowNodeResult.continue({"produced" => json_str("data-from-producer")})
        end)
        .step(Ocawe::Workflow::WorkflowNode.new("consumer", Ocawe::Workflow::NodeKind::Control) do |ctx|
          prev_result = ctx.get_node_result("producer")
          consumed = prev_result.try(&.["produced"]?.try(&.as_s?)) || "nothing"
          Ocawe::Workflow::WorkflowNodeResult.continue({"consumed" => json_str(consumed)})
        end)
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-node-results")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["consumed"].as_s.should eq("data-from-producer")
    end
  end

  describe "init data preservation" do
    it "preserves init data throughout workflow" do
      workflow = Ocawe::Workflow.create_workflow("e2e-init-data", "Init data")
      workflow
        .step(Ocawe::Workflow::WorkflowNode.new("check-init", Ocawe::Workflow::NodeKind::Control) do |ctx|
          init_value = ctx.get_init_data["init_param"]?.try(&.as_s?) || "missing"
          Ocawe::Workflow::WorkflowNodeResult.continue({"init_preserved" => json_str(init_value)})
        end)
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-init-data")
      result = run.start(input_data: {"init_param" => json_str("original-value")})
      result.status.should eq("success")
      result.state.not_nil!["init_preserved"].as_s.should eq("original-value")
    end
  end
end
