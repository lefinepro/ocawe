require "./e2e_spec_helper"

# E2E Tests for Voice Operations
#
# Tests voice transcription and synthesis workflow patterns:
# - Voice playground patterns
# - Voice node execution
# - Voice configuration

describe "E2E: Voice Operations" do
  describe "voice-playground" do
    it "creates workflow with voice nodes" do
      # Simulates voice-playground workflow structure
      workflow = Cogni::Workflows::Declarative.create_workflow("voice-playground", "Voice test")
      workflow
        .voice("voice-transcribe", config: {"provider" => json_str("openai")})
        .voice("voice-synthesize", config: {"provider" => json_str("openai"), "speaker" => json_str("alloy")})
        .commit

      workflow.nodes.size.should eq(2)
      workflow.nodes[0].kind.should eq(Cogni::Workflows::Declarative::NodeKind::Voice)
      workflow.nodes[1].kind.should eq(Cogni::Workflows::Declarative::NodeKind::Voice)
    end

    it "executes voice transcription workflow with text input" do
      workflow = Cogni::Workflows::Declarative.create_workflow("voice-transcribe-test", "Voice transcribe test")
      workflow
        .voice("transcribe", config: {"provider" => json_str("openai")})
        .commit

      engine = Cogni::Workflows::Declarative::Engine.new
      engine.register(workflow)

      run = engine.create_run("voice-transcribe-test")
      result = run.start(input_data: {"text" => json_str("Hello voice test")})
      result.status.should eq("success")
      result.state.not_nil!["voice_status"].as_s.should eq("ok")
      result.state.not_nil!["text"].as_s.should eq("Hello voice test")
    end

    it "executes voice synthesis workflow with text input" do
      workflow = Cogni::Workflows::Declarative.create_workflow("voice-synthesize-test", "Voice synthesize test")
      workflow
        .voice("synthesize", config: {"provider" => json_str("openai"), "speaker" => json_str("alloy")})
        .commit

      engine = Cogni::Workflows::Declarative::Engine.new
      engine.register(workflow)

      run = engine.create_run("voice-synthesize-test")
      result = run.start(input_data: {"text" => json_str("Synthesize this text")})
      result.status.should eq("success")
      result.state.not_nil!["voice_operator"].as_s.should eq("openai")
      result.state.not_nil!["speaker"].as_s.should eq("alloy")
    end
  end

  describe "voice node execution" do
    it "processes voice node with text input" do
      workflow = Cogni::Workflows::Declarative.create_workflow("e2e-voice", "Voice test")
      workflow
        .voice("speak", config: {
          "provider" => json_str("openai"),
          "speaker"  => json_str("alloy"),
        })
        .commit

      engine = Cogni::Workflows::Declarative::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-voice")
      result = run.start(input_data: {"text" => json_str("Hello from E2E test")})

      result.status.should eq("success")
      result.state.not_nil!["voice_status"].as_s.should eq("ok")
      result.state.not_nil!["voice_operator"].as_s.should eq("openai")
      result.state.not_nil!["text"].as_s.should eq("Hello from E2E test")
    end

    it "handles voice node in full workflow" do
      workflow = Cogni::Workflows::Declarative.create_workflow("full-voice-test", "Full voice test")
      workflow
        .then(Cogni::Workflows::Declarative::WorkflowNode.new("setup", Cogni::Workflows::Declarative::NodeKind::Control) do |_ctx|
          Cogni::Workflows::Declarative::WorkflowNodeResult.continue({"prepared" => json_bool(true)})
        end)
        .voice("voice", config: {"provider" => json_str("openai")})
        .then(Cogni::Workflows::Declarative::WorkflowNode.new("after-voice", Cogni::Workflows::Declarative::NodeKind::Control) do |ctx|
          voice_ok = ctx.state["voice_status"]?.try(&.as_s?) == "ok"
          Cogni::Workflows::Declarative::WorkflowNodeResult.continue({"voice_completed" => json_bool(voice_ok)})
        end)
        .commit

      engine = Cogni::Workflows::Declarative::Engine.new
      engine.register(workflow)

      run = engine.create_run("full-voice-test")
      result = run.start(input_data: {"text" => json_str("voice test")})
      result.status.should eq("success")
      result.state.not_nil!["voice_completed"].raw.should eq(true)
    end
  end
end
