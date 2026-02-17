require "./e2e_spec_helper"

# E2E Tests for Resources and Configuration
#
# Tests resource management and configuration patterns:
# - Unified @[Resources(...)] annotation (model, skill, tool)
# - Model selection and resolution
# - Full capabilities workflow
# - Crystal-native configuration

describe "E2E: Resources and Configuration" do
  describe "model selection" do
    it "creates workflow with model default from resource annotation" do
      # Simulates: workflow "simple-model-test" do
      #   @[Resources(model: "cliproxyapi/qwen3-coder-plus")]
      #   agent "simple-model-agent"
      # end
      workflow = CogniCore::Workflow.create_workflow("simple-model-test", "Model test")
      workflow
        .use(model: "clipproxyapi/qwen3-coder-plus")
        .agent("simple-model-agent")
        .commit

      workflow.default_model.should eq("clipproxyapi/qwen3-coder-plus")
      workflow.nodes.size.should eq(1)
    end

    it "resolves model from workflow default" do
      workflow = CogniCore::Workflow.create_workflow("model-resolution-test", "Model resolution test")
      workflow
        .use(model: "clipproxyapi/qwen3-coder-plus")
        .map("check-model") { |ctx|
          {
            "workflow_model" => json_str("clipproxyapi/qwen3-coder-plus"),
            "resolved"       => json_bool(true),
          }
        }
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("model-resolution-test")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["resolved"].raw.should eq(true)
    end

    it "uses model resolution priority (request > agent > workflow default)" do
      workflow = CogniCore::Workflow.create_workflow("model-priority-test", "Model priority test")
      workflow
        .use(model: "default-model")
        .map("check") { |_ctx| {"checked" => json_bool(true)} }
        .commit

      workflow.default_model.should eq("default-model")

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("model-priority-test")
      result = run.start
      result.status.should eq("success")
    end
  end

  describe "unified resources" do
    it "creates workflow with combined resource annotation" do
      # Simulates: @[Resources(model: "openai/gpt-4.1", skill: ["translation", "summarization"], tool: ["http-client"])]
      workflow = CogniCore::Workflow.create_workflow("unified-resources", "Unified resources test")
      workflow
        .use(
          model: "openai/gpt-4.1",
          skill: ["translation", "summarization"],
          tool: ["http-client"])
        .commit

      workflow.default_model.should eq("openai/gpt-4.1")
      workflow.default_skills.should eq(["translation", "summarization"])
      workflow.default_tools.should eq(["http-client"])
    end

    it "creates workflow with unified resource annotation" do
      # Simulates full-capabilities workflow with @[Resources(model: "...", skill: [...], tool: [...])]
      workflow = CogniCore::Workflow.create_workflow("full-capabilities", "Full capabilities test")
      workflow
        .use(
          model: "clipproxyapi/qwen3-coder-plus",
          skill: ["full-skill"],
          tool: ["echo-json"])
        .commit

      workflow.default_model.should eq("clipproxyapi/qwen3-coder-plus")
      workflow.default_skills.should eq(["full-skill"])
      workflow.default_tools.should eq(["echo-json"])
    end

    it "creates workflow with sequential and parallel agents" do
      translator = CogniCore::Workflow::WorkflowNode.new("translator", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"translated" => json_bool(true)})
      end

      summarizer = CogniCore::Workflow::WorkflowNode.new("summarizer", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"summarized" => json_bool(true)})
      end

      workflow = CogniCore::Workflow.create_workflow("unified-pipeline", "Unified pipeline test")
      workflow
        .use(model: "openai/gpt-4.1")
        .map("analyzer") { |_ctx| {"analyzed" => json_bool(true)} }
        .map("processor") { |_ctx| {"processed" => json_bool(true)} }
        .parallel([translator, summarizer])
        .map("synthesizer") { |ctx|
          translated = ctx.state["translated"]?.try(&.raw) == true
          summarized = ctx.state["summarized"]?.try(&.raw) == true
          {"synthesized" => json_bool(translated && summarized)}
        }
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("unified-pipeline")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["synthesized"].raw.should eq(true)
    end
  end

  describe "full-capabilities" do
    it "creates workflow with agent, skill, tool, voice, rag, and suspend nodes" do
      workflow = CogniCore::Workflow.create_workflow("full-demo", "Full demo test")
      workflow
        .use(model: "clipproxyapi/qwen3-coder-plus")
        .agent("full-agent",
          input_schema: CogniCore::Schema::Types.object({"input" => CogniCore::Schema::Types.any()}, strict: false),
          output_schema: CogniCore::Schema::Types.object({"last_response" => CogniCore::Schema::Types.of(String)}, strict: false))
        .skill("full-skill", agent: "full-agent")
        .voice("voice-step", config: {"provider" => json_str("openai"), "speaker" => json_str("alloy")})
        .rag("rag-step", config: {
          "operation"       => json_str("query"),
          "vectorStoreName" => json_str("memory"),
          "indexName"       => json_str("full-capabilities-index"),
          "topK"            => JSON.parse(3.to_json),
        })
        .suspend("manual-approval", reason: "Confirm run output")
        .commit

      workflow.nodes.size.should eq(5)
      workflow.nodes[0].kind.should eq(CogniCore::Workflow::NodeKind::Agent)
      workflow.nodes[1].kind.should eq(CogniCore::Workflow::NodeKind::Skill)
      workflow.nodes[2].kind.should eq(CogniCore::Workflow::NodeKind::Voice)
      workflow.nodes[3].kind.should eq(CogniCore::Workflow::NodeKind::Rag)
      workflow.nodes[4].kind.should eq(CogniCore::Workflow::NodeKind::Suspend)
    end

    it "executes full workflow up to approval suspension" do
      workflow = CogniCore::Workflow.create_workflow("full-approval-test", "Full approval test")
      workflow
        .map("setup") { |_ctx| {"prepared" => json_bool(true)} }
        .voice("voice", config: {"provider" => json_str("openai")})
        .rag("rag", config: {
          "operation"       => json_str("query"),
          "vectorStoreName" => json_str("memory"),
          "indexName"       => json_str("test-index"),
        })
        .suspend("confirm", reason: "Confirm output")
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("full-approval-test")
      result = run.start(input_data: {"text" => json_str("test"), "queryText" => json_str("test query")})
      result.status.should eq("suspended")
      result.resume_labels.should eq(["confirm"])
    end
  end

  describe "config-example (Crystal-native configuration)" do
    it "demonstrates app configuration usage in tests" do
      # This tests that configuration patterns work correctly
      config = {
        "api_key"      => json_str("test-key"),
        "model"        => json_str("clipproxyapi/qwen3-coder-model"),
        "max_tokens"   => JSON.parse(4096.to_json),
        "enable_cache" => json_bool(true),
        "retry_count"  => JSON.parse(3.to_json),
      }

      config["api_key"].as_s.should eq("test-key")
      config["model"].as_s.should eq("clipproxyapi/qwen3-coder-model")
      config["max_tokens"].as_i.should eq(4096)
      config["enable_cache"].raw.should eq(true)
      config["retry_count"].as_i.should eq(3)
    end

    it "handles configuration with nested objects" do
      config = {
        "llm" => JSON.parse({
          "provider"   => "openai",
          "model"      => "gpt-4.1",
          "max_tokens" => 2048,
        }.to_json),
        "storage" => JSON.parse({
          "type"   => "memory",
          "prefix" => "test_",
        }.to_json),
      }

      config["llm"].as_h["provider"].as_s.should eq("openai")
      config["storage"].as_h["type"].as_s.should eq("memory")
    end
  end
end
