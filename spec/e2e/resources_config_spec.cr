require "./e2e_spec_helper"

describe "E2E: Workflow Configuration" do
  it "uses explicit agent model from workflow DSL" do
    ENV["COGNICORE_MOCK_LLM"] = "1"

    begin
      workflow = Ocawe::Workflow.create_workflow("workflow-model-inline", "Model inline")
      workflow
        .agent("model-agent",
          model: "openai/gpt-4.1-mini",
          prompt: "Test",
        )
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      result = engine.create_run("workflow-model-inline").start(input_data: {"task" => json_str("test")})
      result.status.should eq("success")
      result.state.not_nil!["last_model"].as_s.should eq("openai/gpt-4.1-mini")
    ensure
      ENV.delete("COGNICORE_MOCK_LLM")
    end
  end

  it "gives request model higher priority than agent model" do
    ENV["COGNICORE_MOCK_LLM"] = "1"

    begin
      workflow = Ocawe::Workflow.create_workflow("workflow-model-priority", "Model priority")
      workflow
        .agent("priority-agent", model: "openai/gpt-4.1", prompt: "Test")
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      result = engine.create_run("workflow-model-priority").start(input_data: {
        "task"  => json_str("override"),
        "model" => json_str("openai/gpt-4.1-nano"),
      })
      result.status.should eq("success")
      result.state.not_nil!["last_model"].as_s.should eq("openai/gpt-4.1-nano")
    ensure
      ENV.delete("COGNICORE_MOCK_LLM")
    end
  end

  it "stores per-agent models in pipeline flow" do
    ENV["COGNICORE_MOCK_LLM"] = "1"

    begin
      workflow = Ocawe::Workflow.create_workflow("workflow-agent-matrix", "Agent matrix")
      workflow
        .agent("first-agent", model: "openai/gpt-4.1-mini", prompt: "First step")
        .step(Ocawe::Workflow::WorkflowNode.new("capture-model", Ocawe::Workflow::NodeKind::Control) do |ctx|
          first_model = ctx.state["last_model"]?.try(&.as_s?) || ""
          Ocawe::Workflow::WorkflowNodeResult.continue({"first_model" => json_str(first_model)})
        end)
        .agent("second-agent", model: "openai/gpt-4.1", prompt: "Second step")
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      result = engine.create_run("workflow-agent-matrix").start(input_data: {"task" => json_str("pipeline")})
      result.status.should eq("success")
      result.state.not_nil!["first_model"].as_s.should eq("openai/gpt-4.1-mini")
      result.state.not_nil!["last_model"].as_s.should eq("openai/gpt-4.1")
    ensure
      ENV.delete("COGNICORE_MOCK_LLM")
    end
  end

  it "creates workflow with agent, skill, voice, rag, and suspend nodes" do
    workflow = Ocawe::Workflow.create_workflow("full-demo", "Full demo test")
    workflow
      .agent("full-agent",
        model: "clipproxyapi/qwen3-coder-plus",
        input_schema: Ocawe::Workflows::DSL::Types.object({"input" => Ocawe::Workflows::DSL::Types.any()}, strict: false),
        output_schema: Ocawe::Workflows::DSL::Types.object({"last_response" => Ocawe::Workflows::DSL::Types.of(String)}, strict: false))
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
    workflow.nodes[0].kind.should eq(Ocawe::Workflow::NodeKind::Agent)
    workflow.nodes[1].kind.should eq(Ocawe::Workflow::NodeKind::Skill)
    workflow.nodes[2].kind.should eq(Ocawe::Workflow::NodeKind::Voice)
    workflow.nodes[3].kind.should eq(Ocawe::Workflow::NodeKind::Rag)
    workflow.nodes[4].kind.should eq(Ocawe::Workflow::NodeKind::Suspend)
  end

  it "executes full workflow up to approval suspension" do
    workflow = Ocawe::Workflow.create_workflow("full-approval-test", "Full approval test")
    workflow
      .step(Ocawe::Workflow::WorkflowNode.new("setup", Ocawe::Workflow::NodeKind::Control) do |_ctx|
        Ocawe::Workflow::WorkflowNodeResult.continue({"prepared" => json_bool(true)})
      end)
      .voice("voice", config: {"provider" => json_str("openai")})
      .rag("rag", config: {
        "operation"       => json_str("query"),
        "vectorStoreName" => json_str("memory"),
        "indexName"       => json_str("test-index"),
      })
      .suspend("confirm", reason: "Confirm output")
      .commit

    engine = Ocawe::Workflow::Engine.new
    engine.register(workflow)

    run = engine.create_run("full-approval-test")
    result = run.start(input_data: {"text" => json_str("test"), "queryText" => json_str("test query")})
    result.status.should eq("suspended")
    result.resume_labels.should eq(["confirm"])
  end

  describe "config-example (Crystal-native configuration)" do
    it "demonstrates app configuration usage in tests" do
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
