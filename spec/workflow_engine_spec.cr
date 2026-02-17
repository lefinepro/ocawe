require "./spec_helper"


describe Cogni::Workflows::Declarative::Engine do
  it "runs start/resume/cancel/time_travel lifecycle" do
    workflow = Cogni::Workflows::Declarative.create_workflow("wf-test", "test workflow")

    workflow
      .then(Cogni::Workflows::Declarative::WorkflowNode.new("node-1", Cogni::Workflows::Declarative::NodeKind::Control) do |_ctx|
        Cogni::Workflows::Declarative::WorkflowNodeResult.continue({"value" => json_str("ok")})
      end)
      .suspend("approval")
      .then(Cogni::Workflows::Declarative::WorkflowNode.new("final", Cogni::Workflows::Declarative::NodeKind::Control) do |_ctx|
        Cogni::Workflows::Declarative::WorkflowNodeResult.continue({"done" => json_bool(true)})
      end)
      .commit

    engine = Cogni::Workflows::Declarative::Engine.new
    engine.register(workflow)

    run = engine.create_run("wf-test")
    start_result = run.start
    start_result.status.should eq("suspended")
    start_result.resume_labels.should eq(["approval"])

    resumed = run.resume(resume_data: {
      "approved" => json_bool(true),
      "comment"  => json_str("approved"),
    })
    resumed.status.should eq("success")
    resumed.state.not_nil!["done"].raw.should eq(true)

    timed = run.time_travel(node: "node-1", input_data: {"time_travel" => json_bool(true)})
    timed.status.should eq("suspended")

    cancelled = run.cancel
    cancelled.status.should eq("cancelled")
  end

  it "supports sequential and parallel control nodes" do
    workflow = Cogni::Workflows::Declarative.create_workflow("wf-controls", "control nodes")

    parallel_continue = Cogni::Workflows::Declarative::WorkflowNode.new("parallel-continue", Cogni::Workflows::Declarative::NodeKind::Control) do |_ctx|
      Cogni::Workflows::Declarative::WorkflowNodeResult.continue({"p1" => json_str("ok")})
    end
    parallel_suspend = Cogni::Workflows::Declarative::WorkflowNode.new("parallel-suspend", Cogni::Workflows::Declarative::NodeKind::Control) do |_ctx|
      Cogni::Workflows::Declarative::WorkflowNodeResult.suspend(
        {"type" => json_str("human_approval")},
        resume_label: "approval:parallel-suspend",
      )
    end

    workflow
      .then(Cogni::Workflows::Declarative::WorkflowNode.new("seed", Cogni::Workflows::Declarative::NodeKind::Control) do |_ctx|
        Cogni::Workflows::Declarative::WorkflowNodeResult.continue({"value" => json_str("v1")})
      end)
      .then(Cogni::Workflows::Declarative::WorkflowNode.new("mapped", Cogni::Workflows::Declarative::NodeKind::Control) do |ctx|
        Cogni::Workflows::Declarative::WorkflowNodeResult.continue({
          "mapped" => json_str("#{ctx.get_node_result("seed").try(&.["value"]?.try(&.as_s?)) || "none"}:#{ctx.get_init_data["value"]?.try(&.as_s?) || "init-none"}"),
        })
      end)
      .parallel([parallel_continue, parallel_suspend])
      .commit

    engine = Cogni::Workflows::Declarative::Engine.new
    engine.register(workflow)

    run = engine.create_run("wf-controls")
    started = run.start(input_data: {"value" => json_str("v1")})
    started.status.should eq("suspended")
    started.resume_labels.not_nil!.includes?("approval:parallel-suspend").should eq(true)
    started.state.not_nil!["mapped"].as_s.should eq("v1:v1")
  end

  it "supports other workflow methods" do
    workflow = Cogni::Workflows::Declarative.create_workflow("wf-methods", "method coverage")

    foreach_node = Cogni::Workflows::Declarative::WorkflowNode.new("foreach-node", Cogni::Workflows::Declarative::NodeKind::Control) do |_ctx|
      Cogni::Workflows::Declarative::WorkflowNodeResult.continue({"foreach_ran" => json_bool(true)})
    end

    workflow
      .then(Cogni::Workflows::Declarative::WorkflowNode.new("then-node", Cogni::Workflows::Declarative::NodeKind::Control) do |_ctx|
        Cogni::Workflows::Declarative::WorkflowNodeResult.continue({"then_ran" => json_bool(true)})
      end)
      .sleep(0)
      .sleep_until(Time.utc.to_unix)
      .foreach(foreach_node)
      .wait_for_event("deploy", "event:deploy")
      .commit

    engine = Cogni::Workflows::Declarative::Engine.new
    engine.register(workflow)

    run = workflow.create_run_async
    started = run.start
    started.status.should eq("suspended")
    started.resume_labels.should eq(["event:deploy"])
    started.state.not_nil!["then_ran"].raw.should eq(true)
    started.state.not_nil!["foreach_ran"].raw.should eq(true)

    resumed = run.resume(resume_data: {"event_name" => json_str("deploy")})
    resumed.status.should eq("success")
  end

  it "runs function nodes through run API" do
    Cogni::Workflows::Declarative.register_function("create-sandbox") do |_ctx|
      {
        "tool" => json_any("create-sandbox"),
        "status" => json_any("ok"),
      }
    end

    workflow = Cogni::Workflows::Declarative.create_workflow("wf-runs", "run dispatch")
    workflow
      .run("create-sandbox")
      .commit

    engine = Cogni::Workflows::Declarative::Engine.new
    engine.register(workflow)

    run = engine.create_run("wf-runs")
    result = run.start
    result.status.should eq("success")
    result.state.not_nil!["tool"].as_s.should eq("create-sandbox")
  end

  it "supports function aliases when names collide with system functions" do
    Cogni::Workflows::Declarative.register_system_function("conflict-fn") do |_ctx|
      {"which" => json_any("system")}
    end
    user_alias = Cogni::Workflows::Declarative.register_function("conflict-fn") do |_ctx|
      {"which" => json_any("user")}
    end
    user_alias.should eq("conflict-fn:1")

    workflow = Cogni::Workflows::Declarative.create_workflow("wf-fn-collision", "function collision")
    workflow
      .run("conflict-fn")
      .run("conflict-fn:1")
      .commit

    engine = Cogni::Workflows::Declarative::Engine.new
    engine.register(workflow)

    result = engine.create_run("wf-fn-collision").start
    result.status.should eq("success")
    result.state.not_nil!["which"].as_s.should eq("user")
  end

  it "supports mastra-compatible rag keys and output shape" do
    workflow = Cogni::Workflows::Declarative.create_workflow("wf-rag", "rag compatibility")
    workflow
      .rag("rag-ingest", config: {
        "operation"       => json_str("upsert"),
        "vectorStoreName" => json_str("memory"),
        "indexName"       => json_str("wf-rag-index"),
      })
      .rag("rag-query", config: {
        "operation"       => json_str("query"),
        "vectorStoreName" => json_str("memory"),
        "indexName"       => json_str("wf-rag-index"),
        "topK"            => JSON.parse(5.to_json),
      })
      .commit

    engine = Cogni::Workflows::Declarative::Engine.new
    engine.register(workflow)

    run = engine.create_run("wf-rag")
    result = run.start(input_data: {
      "documents" => JSON.parse(["Crystal is a compiled language", "Mastra supports RAG tools"].to_json),
      "queryText" => json_str("compiled"),
      "topK"      => JSON.parse(3.to_json),
    })
    result.status.should eq("success")

    state = result.state.not_nil!
    state["operation"].as_s.should eq("query")
    state["vectorStoreName"].as_s.should eq("memory")
    state["indexName"].as_s.should eq("wf-rag-index")
    state["queryText"].as_s.should eq("compiled")
    state["topK"].as_i.should eq(3)
    state["sources"].as_a.size.should be > 0
    state["relevantContext"].as_a.size.should be > 0
  end

  it "applies declarative input guardrails for agent nodes" do
    ENV["COGNICORE_MOCK_LLM"] = "1"

    begin
      workflow = Cogni::Workflows::Declarative.create_workflow("wf-guardrails", "guardrails")
      workflow
        .agent(
          "guarded-agent",
          prompt: "system",
          model: "openai/gpt-4.1-mini",
          guardrails_config: {
            "input" => JSON.parse({
              "blocked_terms" => ["forbidden"],
            }.to_json),
          } of String => JSON::Any
        )
        .commit

      engine = Cogni::Workflows::Declarative::Engine.new
      engine.register(workflow)

      blocked = engine.create_run("wf-guardrails").start(input_data: {"task" => json_str("this is forbidden input")})
      blocked.status.should eq("failed")
      blocked.error.not_nil!.message.includes?("guardrail violation").should eq(true)

      allowed = engine.create_run("wf-guardrails").start(input_data: {"task" => json_str("safe content")})
      allowed.status.should eq("success")
    ensure
      ENV.delete("COGNICORE_MOCK_LLM")
    end
  end

  it "accepts crystal dsl validators for agent input schema" do
    ENV["COGNICORE_MOCK_LLM"] = "1"

    begin
      input_schema = Cogni::Workflows::DSL::CrystalDSL.compile(
        "Schema::Types.object({\"input\" => Schema::Types.object({\"task\" => Schema::Types.of(String)})}, strict: false)",
        "wf-schema-input"
      )

      workflow = Cogni::Workflows::Declarative.create_workflow("wf-schema", "schema")
      workflow
        .agent(
          "schema-agent",
          prompt: "system",
          model: "openai/gpt-4.1-mini",
          input_schema: input_schema
        )
        .commit

      engine = Cogni::Workflows::Declarative::Engine.new
      engine.register(workflow)

      invalid = engine.create_run("wf-schema").start(input_data: {"query" => json_str("missing task")})
      invalid.status.should eq("failed")
      invalid.error.not_nil!.message.includes?("$.input.input.task is required").should eq(true)

      valid = engine.create_run("wf-schema").start(input_data: {"task" => json_str("present")})
      valid.status.should eq("success")
    ensure
      ENV.delete("COGNICORE_MOCK_LLM")
    end
  end

  it "resolves model with request override first, then agent markdown model, then workflow default" do
    ENV["COGNICORE_MOCK_LLM"] = "1"

    begin
      workflow = Cogni::Workflows::Declarative.create_workflow("wf-models", "model selection")
      workflow
        .use(model: "openai/gpt-4.1-mini")
        .agent("model-agent", prompt: "system", model: "openai/gpt-4.1")
        .commit

      engine = Cogni::Workflows::Declarative::Engine.new
      engine.register(workflow)

      run_agent_model = engine.create_run("wf-models")
      result_agent_model = run_agent_model.start(input_data: {"task" => json_str("agent-model")})
      result_agent_model.status.should eq("success")
      result_agent_model.state.not_nil!["last_model"].as_s.should eq("openai/gpt-4.1")

      run_request_model = engine.create_run("wf-models")
      result_request_model = run_request_model.start(input_data: {
        "task"  => json_str("request-model"),
        "model" => json_str("openai/gpt-4.1-nano"),
      })
      result_request_model.status.should eq("success")
      result_request_model.state.not_nil!["last_model"].as_s.should eq("openai/gpt-4.1-nano")

      workflow_default_only = Cogni::Workflows::Declarative.create_workflow("wf-model-default", "model selection default")
      workflow_default_only
        .use(model: "openai/gpt-4.1-mini")
        .agent("model-agent-default", prompt: "system")
        .commit
      engine.register(workflow_default_only)

      run_default_model = engine.create_run("wf-model-default")
      result_default_model = run_default_model.start(input_data: {"task" => json_str("default-model")})
      result_default_model.status.should eq("success")
      result_default_model.state.not_nil!["last_model"].as_s.should eq("openai/gpt-4.1-mini")
    ensure
      ENV.delete("COGNICORE_MOCK_LLM")
    end
  end

  it "passes previous function output as input envelope for next function" do
    Cogni::Workflows::Declarative.register_function("agent_step_one") do |_ctx|
      Cogni::Workflows::Declarative::AgentResult.new(
        agent_type: "fn-agent",
        content: "step-one-output",
      )
    end

    Cogni::Workflows::Declarative.register_function("agent_step_two") do |ctx|
      previous = ctx.input_data["input"]?.try(&.as_h?) || {} of String => JSON::Any
      received = previous["content"]?.try(&.as_s?) || "missing"
      Cogni::Workflows::Declarative::AgentResult.new(
        agent_type: "fn-agent",
        content: "seen:#{received}",
      )
    end

    workflow = Cogni::Workflows::Declarative.create_workflow("wf-run-chain", "function chaining")
    workflow
      .run("agent_step_one")
      .run("agent_step_two")
      .commit

    engine = Cogni::Workflows::Declarative::Engine.new
    engine.register(workflow)

    result = engine.create_run("wf-run-chain").start(input_data: {"task" => json_str("demo")})
    result.status.should eq("success")
    result.state.not_nil!["content"].as_s.should eq("seen:step-one-output")
  end
end
