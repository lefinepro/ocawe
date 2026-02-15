require "./spec_helper"


describe CogniCore::Workflow::Engine do
  it "runs start/resume/cancel/time_travel lifecycle" do
    workflow = CogniCore::Workflow.create_workflow("wf-test", "test workflow")

    workflow
      .custom("node-1") { |_ctx| CogniCore::Workflow::WorkflowNodeResult.continue({"value" => json_str("ok")}) }
      .approve("approval")
      .custom("final") { |_ctx| CogniCore::Workflow::WorkflowNodeResult.continue({"done" => json_bool(true)}) }
      .commit

    engine = CogniCore::Workflow::Engine.new
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

  it "supports mastra-like branch/map/parallel semantics" do
    workflow = CogniCore::Workflow.create_workflow("wf-mastra", "mastra methods")

    branch_true = CogniCore::Workflow::WorkflowNode.new("branch-true", CogniCore::Workflow::NodeKind::Custom) do |_ctx|
      CogniCore::Workflow::WorkflowNodeResult.continue({"branch" => json_str("true")})
    end
    branch_fallback = CogniCore::Workflow::WorkflowNode.new("branch-fallback", CogniCore::Workflow::NodeKind::Custom) do |_ctx|
      CogniCore::Workflow::WorkflowNodeResult.continue({"branch" => json_str("fallback")})
    end

    parallel_continue = CogniCore::Workflow::WorkflowNode.new("parallel-continue", CogniCore::Workflow::NodeKind::Custom) do |_ctx|
      CogniCore::Workflow::WorkflowNodeResult.continue({"p1" => json_str("ok")})
    end
    parallel_suspend = CogniCore::Workflow::WorkflowNode.new("parallel-suspend", CogniCore::Workflow::NodeKind::Custom) do |_ctx|
      CogniCore::Workflow::WorkflowNodeResult.suspend(
        {"type" => json_str("human_approval")},
        resume_label: "approval:parallel-suspend",
      )
    end

    workflow
      .custom("seed") { |_ctx| CogniCore::Workflow::WorkflowNodeResult.continue({"value" => json_str("v1")}) }
      .branch([
        {->(ctx : CogniCore::Workflow::NodeContext) { ctx.input_data["value"]?.try(&.as_s?) == "v1" }, branch_true},
        {"false", branch_fallback},
        {false, branch_fallback},
      ] of Tuple(CogniCore::Workflow::BranchCondition, CogniCore::Workflow::WorkflowNode), otherwise_node: branch_fallback)
      .map("mapped") do |ctx|
        {
          "mapped" => json_str("#{ctx.get_node_result("seed").try(&.["value"]?.try(&.as_s?)) || "none"}:#{ctx.get_init_data["value"]?.try(&.as_s?) || "init-none"}"),
        }
      end
      .parallel([parallel_continue, parallel_suspend])
      .commit

    engine = CogniCore::Workflow::Engine.new
    engine.register(workflow)

    run = engine.create_run("wf-mastra")
    started = run.start(input_data: {"value" => json_str("v1")})
    started.status.should eq("suspended")
    started.resume_labels.not_nil!.includes?("approval:parallel-suspend").should eq(true)
    started.state.not_nil!["mapped"].as_s.should eq("v1:v1")
  end

  it "supports other workflow methods" do
    workflow = CogniCore::Workflow.create_workflow("wf-methods", "method coverage")

    do_counter = 0
    until_counter = 0
    foreach_node = CogniCore::Workflow::WorkflowNode.new("foreach-node", CogniCore::Workflow::NodeKind::Custom) do |_ctx|
      CogniCore::Workflow::WorkflowNodeResult.continue({"foreach_ran" => json_bool(true)})
    end

    workflow
      .then(CogniCore::Workflow::WorkflowNode.new("then-node", CogniCore::Workflow::NodeKind::Custom) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"then_ran" => json_bool(true)})
      end)
      .sleep(0)
      .sleep_until(Time.utc.to_unix)
      .dowhile(
        CogniCore::Workflow::WorkflowNode.new("do-node", CogniCore::Workflow::NodeKind::Custom) do |_ctx|
          do_counter += 1
          CogniCore::Workflow::WorkflowNodeResult.continue({"dowhile_runs" => json_str(do_counter.to_s)})
        end,
        ->(_ctx : CogniCore::Workflow::NodeContext) { do_counter < 2 }
      )
      .dountil(
        CogniCore::Workflow::WorkflowNode.new("until-node", CogniCore::Workflow::NodeKind::Custom) do |_ctx|
          until_counter += 1
          CogniCore::Workflow::WorkflowNodeResult.continue({"dountil_runs" => json_str(until_counter.to_s)})
        end,
        ->(_ctx : CogniCore::Workflow::NodeContext) { until_counter >= 2 }
      )
      .foreach(foreach_node)
      .wait_for_event("deploy", "event:deploy")
      .commit

    engine = CogniCore::Workflow::Engine.new
    engine.register(workflow)

    run = workflow.create_run_async
    started = run.start
    started.status.should eq("suspended")
    started.resume_labels.should eq(["event:deploy"])
    started.state.not_nil!["then_ran"].raw.should eq(true)
    started.state.not_nil!["foreach_ran"].raw.should eq(true)
    started.state.not_nil!["dowhile_runs"].as_s.should eq("2")
    started.state.not_nil!["dountil_runs"].as_s.should eq("2")

    resumed = run.resume(resume_data: {"event_name" => json_str("deploy")})
    resumed.status.should eq("success")
  end

  it "runs tool nodes through direct crystal tool functions" do
    CogniCore::Workflow.register_tool("tool_create_sandbox") do |_ctx|
      {
        "tool" => json_any("create-sandbox"),
        "status" => json_any("ok"),
      }
    end

    workflow = CogniCore::Workflow.create_workflow("wf-tools", "tool dispatch")
    workflow
      .tool("tool_create_sandbox")
      .commit

    engine = CogniCore::Workflow::Engine.new
    engine.register(workflow)

    run = engine.create_run("wf-tools")
    result = run.start
    result.status.should eq("success")
    result.state.not_nil!["tool"].as_s.should eq("create-sandbox")
  end

  it "rejects crystal tool nodes without tool_ prefix" do
    workflow = CogniCore::Workflow.create_workflow("wf-tools-invalid", "tool dispatch invalid")
    expect_raises(Exception, /starting with tool_/) do
      workflow.tool("create-sandbox")
    end
  end

  it "supports mastra-compatible rag keys and output shape" do
    workflow = CogniCore::Workflow.create_workflow("wf-rag", "rag compatibility")
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

    engine = CogniCore::Workflow::Engine.new
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
      workflow = CogniCore::Workflow.create_workflow("wf-guardrails", "guardrails")
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

      engine = CogniCore::Workflow::Engine.new
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
      input_schema = CogniCore::Schema::CrystalDSL.compile(
        "Schema::Types.object({\"task\" => Schema::Types.of(String)})",
        "wf-schema-input"
      )

      workflow = CogniCore::Workflow.create_workflow("wf-schema", "schema")
      workflow
        .agent(
          "schema-agent",
          prompt: "system",
          model: "openai/gpt-4.1-mini",
          input_schema: input_schema
        )
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      invalid = engine.create_run("wf-schema").start(input_data: {"query" => json_str("missing task")})
      invalid.status.should eq("failed")
      invalid.error.not_nil!.message.includes?("$.input.task is required").should eq(true)

      valid = engine.create_run("wf-schema").start(input_data: {"task" => json_str("present")})
      valid.status.should eq("success")
    ensure
      ENV.delete("COGNICORE_MOCK_LLM")
    end
  end

  it "resolves model with request override first, then agent markdown model, then workflow default" do
    ENV["COGNICORE_MOCK_LLM"] = "1"

    begin
      workflow = CogniCore::Workflow.create_workflow("wf-models", "model selection")
      workflow
        .use_model("openai/gpt-4.1-mini")
        .agent("model-agent", prompt: "system", model: "openai/gpt-4.1")
        .commit

      engine = CogniCore::Workflow::Engine.new
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

      workflow_default_only = CogniCore::Workflow.create_workflow("wf-model-default", "model selection default")
      workflow_default_only
        .use_model("openai/gpt-4.1-mini")
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
end
