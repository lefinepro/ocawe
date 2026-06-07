require "./spec_helper"
require "file_utils"


describe Ocawe::Workflow::ExecExecutor do
  it "rejects non-mcp refs without runtime" do
    executor = Ocawe::Workflow::ExecExecutor.new
    ctx = Ocawe::Workflow::NodeContext.new(
      workflow_id: "wf",
      run_id: "run_1",
      node_id: "create_sandbox",
      input_data: {} of String => JSON::Any,
      state: {} of String => JSON::Any,
    )

    expect_raises(Exception, /exec requires runtime/) do
      executor.exec("create_sandbox", ctx)
    end
  end

  it "runs external scripts with runtime metadata" do
    executor = Ocawe::Workflow::ExecExecutor.new
    ctx = Ocawe::Workflow::NodeContext.new(
      workflow_id: "wf",
      run_id: "run_2",
      node_id: "external-tool",
      input_data: {} of String => JSON::Any,
      state: {} of String => JSON::Any,
    )
    runtime = {"shell" => json_any("bash")} of String => JSON::Any

    result = executor.exec(
      "tools/create-sandbox.sh",
      ctx,
      runtime: runtime,
      workflow_root: "./shards/examples/sandbox-example",
    )
    result["status"].as_s.should eq("ok")
  end

  it "fails when external run emits invalid json" do
    dir = "/tmp/ocawecore-test-tools"
    FileUtils.mkdir_p(dir)
    script = File.join(dir, "invalid.sh")
    File.write(script, "#!/usr/bin/env bash\nset -euo pipefail\necho not-json\n")
    File.chmod(script, 0o755)

    executor = Ocawe::Workflow::ExecExecutor.new
    ctx = Ocawe::Workflow::NodeContext.new(
      workflow_id: "wf",
      run_id: "run_3",
      node_id: "external-invalid",
      input_data: {} of String => JSON::Any,
      state: {} of String => JSON::Any,
    )

    runtime = {"shell" => json_any("bash")} of String => JSON::Any
    expect_raises(Exception, /invalid JSON/) do
      executor.exec("invalid.sh", ctx, runtime: runtime, workflow_root: dir)
    end
  end

  it "fails when runtime object is empty" do
    executor = Ocawe::Workflow::ExecExecutor.new
    ctx = Ocawe::Workflow::NodeContext.new(
      workflow_id: "wf",
      run_id: "run_4",
      node_id: "external-empty-runtime",
      input_data: {"task" => json_any("hello")},
      state: {"task" => json_any("hello")},
    )

    expect_raises(Exception, /runtime object must contain at least one key/) do
      executor.exec("tools/create-sandbox.sh", ctx, runtime: ({} of String => JSON::Any), workflow_root: "./shards/examples/sandbox-example")
    end
  end
end
