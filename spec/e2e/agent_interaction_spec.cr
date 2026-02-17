require "./e2e_spec_helper"

describe "E2E: Agent Interaction" do
  describe "agent with voice config" do
    it "passes voice configuration to agent result" do
      ENV["COGNICORE_MOCK_LLM"] = "1"

      begin
        workflow = Cogni::Workflows::Declarative.create_workflow("e2e-agent-voice", "Agent with voice")
        workflow
          .agent(
            "voice-agent",
            prompt: "You are a voice-enabled agent",
            model: "openai/gpt-4.1-mini",
            voice_config: {
              "voice_operator" => json_str("openai"),
              "speaker"        => json_str("alloy"),
            }
          )
          .commit

        engine = Cogni::Workflows::Declarative::Engine.new
        engine.register(workflow)

        result = engine.create_run("e2e-agent-voice").start(input_data: {"task" => json_str("Hello")})
        result.status.should eq("success")
        result.state.not_nil!["active_voice"].as_h["voice_operator"].as_s.should eq("openai")
      ensure
        ENV.delete("COGNICORE_MOCK_LLM")
      end
    end
  end

  describe "agent input handling" do
    it "builds user prompt from task field" do
      ENV["COGNICORE_MOCK_LLM"] = "1"

      begin
        workflow = Cogni::Workflows::Declarative.create_workflow("e2e-agent-task", "Agent task input")
        workflow
          .agent("task-agent", prompt: "Process task", model: "openai/gpt-4.1-mini")
          .commit

        engine = Cogni::Workflows::Declarative::Engine.new
        engine.register(workflow)

        result = engine.create_run("e2e-agent-task").start(input_data: {
          "task" => json_str("Analyze this data"),
        })
        result.status.should eq("success")
        result.state.not_nil!["last_response"].as_s.includes?("Analyze this data").should eq(true)
      ensure
        ENV.delete("COGNICORE_MOCK_LLM")
      end
    end

    it "builds user prompt from input object" do
      ENV["COGNICORE_MOCK_LLM"] = "1"

      begin
        workflow = Cogni::Workflows::Declarative.create_workflow("e2e-agent-input-obj", "Agent input object")
        workflow
          .agent("input-agent", prompt: "Process input", model: "openai/gpt-4.1-mini")
          .commit

        engine = Cogni::Workflows::Declarative::Engine.new
        engine.register(workflow)

        result = engine.create_run("e2e-agent-input-obj").start(input_data: {
          "input" => JSON.parse({"content" => "Input content here"}.to_json),
        })
        result.status.should eq("success")
        result.state.not_nil!["last_response"].as_s.includes?("Input content").should eq(true)
      ensure
        ENV.delete("COGNICORE_MOCK_LLM")
      end
    end
  end

  describe "multi-agent workflows" do
    it "chains multiple agents with output passing" do
      ENV["COGNICORE_MOCK_LLM"] = "1"

      begin
        workflow = Cogni::Workflows::Declarative.create_workflow("e2e-multi-agent", "Multi-agent chain")
        workflow
          .use(model: "openai/gpt-4.1-mini")
          .agent("analyzer", prompt: "Analyze input")
          .agent("summarizer", prompt: "Summarize previous analysis")
          .agent("formatter", prompt: "Format for output")
          .commit

        engine = Cogni::Workflows::Declarative::Engine.new
        engine.register(workflow)

        result = engine.create_run("e2e-multi-agent").start(input_data: {
          "task" => json_str("Process document"),
        })
        result.status.should eq("success")
        result.state.not_nil!["last_agent"].as_s.should eq("formatter")

        # Check all agents ran
        outputs = result.state.not_nil!["agent_outputs"].as_h
        outputs.keys.should contain("analyzer")
        outputs.keys.should contain("summarizer")
        outputs.keys.should contain("formatter")
      ensure
        ENV.delete("COGNICORE_MOCK_LLM")
      end
    end
  end
end
