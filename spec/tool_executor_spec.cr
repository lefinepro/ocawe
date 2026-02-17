require "./spec_helper"
require "file_utils"


describe CogniCore::Workflow::RunExecutor do
  it "runs registered functions directly by name" do
    CogniCore::Workflow.register_function("create_sandbox") do |_ctx|
      {
        "tool" => json_any("create-sandbox"),
        "status" => json_any("ok"),
      }
    end

    executor = CogniCore::Workflow::RunExecutor.new
    ctx = CogniCore::Workflow::NodeContext.new(
      workflow_id: "wf",
      run_id: "run_1",
      node_id: "create_sandbox",
      input_data: {} of String => JSON::Any,
      state: {} of String => JSON::Any,
    )

    result = executor.run("create_sandbox", ctx)
    result["tool"].as_s.should eq("create-sandbox")
    result["status"].as_s.should eq("ok")
  end

  it "runs external scripts with runtime metadata" do
    executor = CogniCore::Workflow::RunExecutor.new
    ctx = CogniCore::Workflow::NodeContext.new(
      workflow_id: "wf",
      run_id: "run_2",
      node_id: "external-tool",
      input_data: {} of String => JSON::Any,
      state: {} of String => JSON::Any,
    )
    runtime = {"shell" => json_any("bash")} of String => JSON::Any

    result = executor.run(
      "tools/create-sandbox.sh",
      ctx,
      runtime: runtime,
      workflow_root: "./shards/examples/sandbox-example",
    )
    result["status"].as_s.should eq("ok")
  end

  it "fails when external run emits invalid json" do
    dir = "/tmp/cognicore-test-tools"
    FileUtils.mkdir_p(dir)
    script = File.join(dir, "invalid.sh")
    File.write(script, "#!/usr/bin/env bash\nset -euo pipefail\necho not-json\n")
    File.chmod(script, 0o755)

    executor = CogniCore::Workflow::RunExecutor.new
    ctx = CogniCore::Workflow::NodeContext.new(
      workflow_id: "wf",
      run_id: "run_3",
      node_id: "external-invalid",
      input_data: {} of String => JSON::Any,
      state: {} of String => JSON::Any,
    )

    runtime = {"shell" => json_any("bash")} of String => JSON::Any
    expect_raises(Exception, /invalid JSON/) do
      executor.run("invalid.sh", ctx, runtime: runtime, workflow_root: dir)
    end
  end

  it "runs registered ai generate function by direct name" do
    CogniCore::Workflow.register_function("ai_generate_text") do |ctx|
      {
        "tool" => json_any("ai-generate-text"),
        "model" => json_any(ctx.state["workflow_model"]?.try(&.as_s?) || "missing"),
        "text" => json_any(ctx.state["task"]?.try(&.as_s?) || ""),
      }
    end

    executor = CogniCore::Workflow::RunExecutor.new
    ctx = CogniCore::Workflow::NodeContext.new(
      workflow_id: "wf",
      run_id: "run_4",
      node_id: "ai_generate_text",
      input_data: {"task" => json_any("hello")},
      state: {"task" => json_any("hello"), "workflow_model" => json_any("cliproxyapi/qwen3-coder-plus")},
    )

    result = executor.run("ai_generate_text", ctx)
    result["tool"].as_s.should eq("ai-generate-text")
    result["model"].as_s.should eq("cliproxyapi/qwen3-coder-plus")
    result["text"].as_s.includes?("hello").should eq(true)
  end
end
