require "./e2e_spec_helper"

describe "E2E: Model Selection and AI Integration" do
  describe "model resolution" do
    it "uses request model override over agent and workflow defaults" do
      ENV["COGNICORE_MOCK_LLM"] = "1"

      begin
        workflow = Cogni::Workflow.create_workflow("e2e-model-override", "Model override")
        workflow
          .agent("model-agent", prompt: "Test", model: "openai/gpt-4.1") # agent model
          .commit

        engine = Cogni::Workflow::Engine.new
        engine.register(workflow)

        # With request model override
        result = engine.create_run("e2e-model-override").start(input_data: {
          "task"  => json_str("test"),
          "model" => json_str("openai/gpt-4.1-nano"), # request override
        })
        result.status.should eq("success")
        result.state.not_nil!["last_model"].as_s.should eq("openai/gpt-4.1-nano")

        # Without request override - should use agent model
        result2 = engine.create_run("e2e-model-override").start(input_data: {
          "task" => json_str("test"),
        })
        result2.status.should eq("success")
        result2.state.not_nil!["last_model"].as_s.should eq("openai/gpt-4.1")
      ensure
        ENV.delete("COGNICORE_MOCK_LLM")
      end
    end

    it "falls back to workflow default when no agent model specified" do
      ENV["COGNICORE_MOCK_LLM"] = "1"

      begin
        workflow = Cogni::Workflow.create_workflow("e2e-model-fallback", "Model fallback")
        workflow
          .agent("fallback-agent", prompt: "Test", model: "openai/gpt-4.1-mini") # no model specified
          .commit

        engine = Cogni::Workflow::Engine.new
        engine.register(workflow)

        result = engine.create_run("e2e-model-fallback").start(input_data: {
          "task" => json_str("test"),
        })
        result.status.should eq("success")
        result.state.not_nil!["last_model"].as_s.should eq("openai/gpt-4.1-mini")
      ensure
        ENV.delete("COGNICORE_MOCK_LLM")
      end
    end
  end

  describe "agent model and execution" do
    it "uses explicit agent model" do
      ENV["COGNICORE_MOCK_LLM"] = "1"

      begin
        workflow = Cogni::Workflow.create_workflow("e2e-use-unified", "Unified use")
        workflow
          .agent("unified-agent", prompt: "Test", model: "openai/gpt-4.1-mini")
          .commit

        engine = Cogni::Workflow::Engine.new
        engine.register(workflow)

        result = engine.create_run("e2e-use-unified").start(input_data: {"task" => json_str("test")})
        result.status.should eq("success")
      ensure
        ENV.delete("COGNICORE_MOCK_LLM")
      end
    end
  end
end
