require "./spec_helper"
require "http/server"

describe Ocawe::Workflow::Engine do
  it "runs API nodes and lets later workflow steps read previous node results by index and id" do
    server = HTTP::Server.new do |context|
      case {context.request.method, context.request.path}
      when {"GET", "/weather"}
        context.response.content_type = "application/json"
        context.response.print({"temperature" => 12, "current" => {"temperature_2m" => 12}}.to_json)
      when {"POST", "/sink"}
        body = context.request.body.try(&.gets_to_end).to_s
        context.response.content_type = "application/json"
        context.response.print({"received" => JSON.parse(body), "ok" => true}.to_json)
      else
        context.response.status_code = 404
        context.response.print({"error" => "not found"}.to_json)
      end
    end
    address = server.bind_tcp("127.0.0.1", 0)
    port = address.port
    spawn { server.listen }
    Fiber.yield

    workflow = Ocawe::Workflow.create_workflow("wf-api", "api nodes")
    workflow
      .get("http://127.0.0.1:#{port}/weather", id: "weather")
      .while_do(
        "step[\"weather\"].current.temperature_2m > 0",
        [
          Ocawe::RegistryApi.build_node(
            workflow,
            "api",
            "sink",
            config: {
              "method" => JSON.parse("POST".to_json),
              "url"    => JSON.parse("http://127.0.0.1:#{port}/sink".to_json),
              "body"   => JSON.parse("step[\"weather\"].current".to_json),
            } of String => JSON::Any,
          ),
        ],
        max_iterations: 1
      )
      .commit

    run = workflow.create_run_async
    result = run.start
    result.status.should eq("success")
    state = result.state.not_nil!
    state["temperature"].as_i.should eq(12)
    state["received"].as_h["temperature_2m"].as_i.should eq(12)
    run.get_current_run.node_results.not_nil!["weather"]["step"].as_s.should eq("weather")
    run.get_current_run.node_results.not_nil!["sink"].should_not be_nil
  ensure
    server.try(&.close)
  end

  it "runs start/resume/cancel/time_travel lifecycle" do
    workflow = Ocawe::Workflow.create_workflow("wf-test", "test workflow")
    workflow
      .step(Ocawe::Workflow::WorkflowNode.new("node-1", Ocawe::Workflow::NodeKind::Control) do |_ctx|
        Ocawe::Workflow::WorkflowNodeResult.continue({"value" => json_str("ok")})
      end)
      .suspend("approval")
      .step(Ocawe::Workflow::WorkflowNode.new("final", Ocawe::Workflow::NodeKind::Control) do |_ctx|
        Ocawe::Workflow::WorkflowNodeResult.continue({"done" => json_bool(true)})
      end)
      .commit

    engine = Ocawe::Workflow::Engine.new
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
    workflow = Ocawe::Workflow.create_workflow("wf-controls", "control nodes")

    parallel_continue = Ocawe::Workflow::WorkflowNode.new("parallel-continue", Ocawe::Workflow::NodeKind::Control) do |_ctx|
      Ocawe::Workflow::WorkflowNodeResult.continue({"p1" => json_str("ok")})
    end
    parallel_suspend = Ocawe::Workflow::WorkflowNode.new("parallel-suspend", Ocawe::Workflow::NodeKind::Control) do |_ctx|
      Ocawe::Workflow::WorkflowNodeResult.suspend(
        {"type" => json_str("human_approval")},
        resume_label: "approval:parallel-suspend",
      )
    end

    workflow
      .step(Ocawe::Workflow::WorkflowNode.new("seed", Ocawe::Workflow::NodeKind::Control) do |_ctx|
        Ocawe::Workflow::WorkflowNodeResult.continue({"value" => json_str("v1")})
      end)
      .step(Ocawe::Workflow::WorkflowNode.new("mapped", Ocawe::Workflow::NodeKind::Control) do |ctx|
        Ocawe::Workflow::WorkflowNodeResult.continue({
          "mapped" => json_str("#{ctx.get_node_result("seed").try(&.["value"]?.try(&.as_s?)) || "none"}:#{ctx.get_init_data["value"]?.try(&.as_s?) || "init-none"}"),
        })
      end)
      .parallel([parallel_continue, parallel_suspend])
      .commit

    engine = Ocawe::Workflow::Engine.new
    engine.register(workflow)

    run = engine.create_run("wf-controls")
    started = run.start(input_data: {"value" => json_str("v1")})
    started.status.should eq("suspended")
    started.resume_labels.not_nil!.includes?("approval:parallel-suspend").should eq(true)
    started.state.not_nil!["mapped"].as_s.should eq("v1:v1")
  end

  it "supports other workflow methods" do
    workflow = Ocawe::Workflow.create_workflow("wf-methods", "method coverage")

    foreach_node = Ocawe::Workflow::WorkflowNode.new("foreach-node", Ocawe::Workflow::NodeKind::Control) do |_ctx|
      Ocawe::Workflow::WorkflowNodeResult.continue({"foreach_ran" => json_bool(true)})
    end

    workflow
      .step(Ocawe::Workflow::WorkflowNode.new("then-node", Ocawe::Workflow::NodeKind::Control) do |_ctx|
        Ocawe::Workflow::WorkflowNodeResult.continue({"then_ran" => json_bool(true)})
      end)
      .sleep(0)
      .sleep_until(Time.utc.to_unix)
      .foreach(foreach_node)
      .wait_for_event("deploy", "event:deploy")
      .commit

    engine = Ocawe::Workflow::Engine.new
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

  it "runs internal function nodes through node kind API" do
    Ocawe::Workflow.register_function("create-sandbox") do |_ctx|
      {
        "tool" => json_any("create-sandbox"),
        "status" => json_any("ok"),
      }
    end
    Ocawe::RegistryApi.node_kind("create-sandbox") do |ctx, _parameters|
      Ocawe::RegistryApi.call_function("create-sandbox", ctx)
    end

    workflow = Ocawe::Workflow.create_workflow("wf-runs", "run dispatch")
    workflow
      .step(Ocawe::NodeKind.new("create-sandbox"), id: "create-sandbox")
      .commit

    engine = Ocawe::Workflow::Engine.new
    engine.register(workflow)

    run = engine.create_run("wf-runs")
    result = run.start
    result.status.should eq("success")
    result.state.not_nil!["tool"].as_s.should eq("create-sandbox")
  end

  it "supports internal node kinds mapped to function aliases" do
    Ocawe::Workflow.register_system_function("conflict-fn") do |_ctx|
      {"which" => json_any("system")}
    end
    user_alias = Ocawe::Workflow.register_function("conflict-fn") do |_ctx|
      {"which" => json_any("user")}
    end
    user_alias.should eq("conflict-fn:1")
    Ocawe::RegistryApi.node_kind("conflict-fn") do |ctx, _parameters|
      Ocawe::RegistryApi.call_function("conflict-fn", ctx)
    end
    Ocawe::RegistryApi.node_kind("conflict-fn:1") do |ctx, _parameters|
      Ocawe::RegistryApi.call_function("conflict-fn:1", ctx)
    end

    workflow = Ocawe::Workflow.create_workflow("wf-fn-collision", "function collision")
    workflow
      .step(Ocawe::NodeKind.new("conflict-fn"), id: "conflict-fn")
      .step(Ocawe::NodeKind.new("conflict-fn:1"), id: "conflict-fn:1")
      .commit

    engine = Ocawe::Workflow::Engine.new
    engine.register(workflow)

    result = engine.create_run("wf-fn-collision").start
    result.status.should eq("success")
    result.state.not_nil!["which"].as_s.should eq("user")
  end

  it "supports mastra-compatible rag keys and output shape" do
    workflow = Ocawe::Workflow.create_workflow("wf-rag", "rag compatibility")
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

    engine = Ocawe::Workflow::Engine.new
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
      workflow = Ocawe::Workflow.create_workflow("wf-guardrails", "guardrails")
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

      engine = Ocawe::Workflow::Engine.new
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
      input_schema = Ocawe::Workflows::DSL::CrystalDSL.compile(
        "Schema::Types.object({\"input\" => Schema::Types.object({\"task\" => Schema::Types.of(String)})}, strict: false)",
        "wf-schema-input"
      )

      workflow = Ocawe::Workflow.create_workflow("wf-schema", "schema")
      workflow
        .agent(
          "schema-agent",
          prompt: "system",
          model: "openai/gpt-4.1-mini",
          input_schema: input_schema
        )
        .commit

      engine = Ocawe::Workflow::Engine.new
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
      workflow = Ocawe::Workflow.create_workflow("wf-models", "model selection")
      workflow
        .agent("model-agent", prompt: "system", model: "openai/gpt-4.1")
        .commit

      engine = Ocawe::Workflow::Engine.new
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

      workflow_default_only = Ocawe::Workflow.create_workflow("wf-model-default", "model selection default")
      workflow_default_only
        .agent("model-agent-default", prompt: "system", model: "openai/gpt-4.1-mini")
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
