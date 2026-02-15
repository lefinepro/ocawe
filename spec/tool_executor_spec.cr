require "./spec_helper"
require "file_utils"

private def json_any(value)
  JSON.parse(value.to_json)
end

describe CogniCore::Workflow::ToolExecutor do
  it "runs crystal tool functions directly by name" do
    executor = CogniCore::Workflow::ToolExecutor.new
    ctx = CogniCore::Workflow::NodeContext.new(
      workflow_id: "wf",
      run_id: "run_1",
      node_id: "tool_create_sandbox",
      input_data: {} of String => JSON::Any,
      state: {} of String => JSON::Any,
    )

    result = executor.run("tool_create_sandbox", ctx)
    result["tool"].as_s.should eq("create-sandbox")
    result["status"].as_s.should eq("ok")
  end

  it "runs external tools with runtime metadata" do
    executor = CogniCore::Workflow::ToolExecutor.new
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
      workflow_root: "./src/workflows/aggregation-workflow",
    )
    result["status"].as_s.should eq("ok")
  end

  it "fails when external tool emits invalid json" do
    dir = "/tmp/cognicore-test-tools"
    FileUtils.mkdir_p(dir)
    script = File.join(dir, "invalid.sh")
    File.write(script, "#!/usr/bin/env bash\nset -euo pipefail\necho not-json\n")
    File.chmod(script, 0o755)

    executor = CogniCore::Workflow::ToolExecutor.new
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

  it "runs built-in ai generate tool by direct function name" do
    ENV["COGNICORE_MOCK_LLM"] = "1"

    begin
      executor = CogniCore::Workflow::ToolExecutor.new
      ctx = CogniCore::Workflow::NodeContext.new(
        workflow_id: "wf",
        run_id: "run_4",
        node_id: "tool_ai_generate_text",
        input_data: {"task" => json_any("hello")},
        state: {"task" => json_any("hello"), "workflow_model" => json_any("openapi/qwen3-coder-plus")},
      )

      result = executor.run("tool_ai_generate_text", ctx)
      result["tool"].as_s.should eq("ai-generate-text")
      result["model"].as_s.should eq("openapi/qwen3-coder-plus")
      result["text"].as_s.includes?("hello").should eq(true)
    ensure
      ENV.delete("COGNICORE_MOCK_LLM")
    end
  end
end
