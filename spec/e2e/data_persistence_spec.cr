require "./e2e_spec_helper"

describe "E2E: Data Persistence and State" do
  describe "state accumulation" do
    it "accumulates state across multiple nodes" do
      workflow = CogniCore::Workflow.create_workflow("e2e-state-accum", "State accumulation")
      workflow
        .map("step-1") { |_ctx| {"value_1" => json_str("one")} }
        .map("step-2") { |ctx|
          prev = ctx.state["value_1"]?.try(&.as_s?) || "none"
          {"value_2" => json_str("two:#{prev}")}
        }
        .map("step-3") { |ctx|
          v1 = ctx.state["value_1"]?.try(&.as_s?) || "none"
          v2 = ctx.state["value_2"]?.try(&.as_s?) || "none"
          {"final" => json_str("#{v1}|#{v2}")}
        }
        .commit

      engine = CogniCore::Workflow::Engine.new
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
      workflow = CogniCore::Workflow.create_workflow("e2e-node-results", "Node results")
      workflow
        .map("producer") { |_ctx| {"produced" => json_str("data-from-producer")} }
        .map("consumer") { |ctx|
          prev_result = ctx.get_node_result("producer")
          consumed = prev_result.try(&.["produced"]?.try(&.as_s?)) || "nothing"
          {"consumed" => json_str(consumed)}
        }
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-node-results")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["consumed"].as_s.should eq("data-from-producer")
    end
  end

  describe "init data preservation" do
    it "preserves init data throughout workflow" do
      workflow = CogniCore::Workflow.create_workflow("e2e-init-data", "Init data")
      workflow
        .map("check-init") { |ctx|
          init_value = ctx.get_init_data["init_param"]?.try(&.as_s?) || "missing"
          {"init_preserved" => json_str(init_value)}
        }
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-init-data")
      result = run.start(input_data: {"init_param" => json_str("original-value")})
      result.status.should eq("success")
      result.state.not_nil!["init_preserved"].as_s.should eq("original-value")
    end
  end
end
