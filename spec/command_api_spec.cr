require "./spec_helper"

describe "Command.register" do
  before_each do
    Ocawe::RegistryApi.reset_all!
  end

  it "registers a compatible handler through the existing lifecycle" do
    handler = ->(ctx : Ocawe::Workflow::NodeContext) : Ocawe::Workflow::RunnableResult do
      {
        "node" => json_str(ctx.node_id),
        "input" => ctx.input_data["value"]?,
      }.compact
    end

    Command.register("set_value", handler).should eq("set_value")

    ctx = Ocawe::Workflow::NodeContext.new(
      workflow_id: "wf-command-api",
      run_id: "run-command-api",
      node_id: "command-node",
      input_data: {"value" => json_str("from-input")} of String => JSON::Any,
      state: {} of String => JSON::Any,
    )

    result = Ocawe::RegistryApi.call_function("set_value", ctx)
    result["node"].as_s.should eq("command-node")
    result["input"].as_s.should eq("from-input")
  end

  it "replays command registrations after a registry reset" do
    handler = ->(_ctx : Ocawe::Workflow::NodeContext) : Ocawe::Workflow::RunnableResult do
      {"status" => json_str("ok")}
    end

    Command.register("persisted_command", handler)
    Ocawe::RegistryApi.reset_all!

    ctx = Ocawe::Workflow::NodeContext.new(
      workflow_id: "wf-command-persistence",
      run_id: "run-command-persistence",
      node_id: "persisted-command",
      input_data: {} of String => JSON::Any,
      state: {} of String => JSON::Any,
    )

    Ocawe::RegistryApi.call_function("persisted_command", ctx)["status"].as_s.should eq("ok")
  end

  it "rejects empty and duplicate command names" do
    handler = ->(_ctx : Ocawe::Workflow::NodeContext) : Ocawe::Workflow::RunnableResult do
      {} of String => JSON::Any
    end

    expect_raises(Exception, /invalid command name/) { Command.register("   ", handler) }
    Command.register("duplicate_command", handler)
    expect_raises(Exception, /command already registered/) { Command.register(" DUPLICATE_COMMAND ", handler) }
  end

  it "does not change legacy duplicate registration behavior" do
    Ocawe::RegistryApi.register_function("legacy_duplicate") { {} of String => JSON::Any }
    Ocawe::RegistryApi.register_function("legacy_duplicate") { {} of String => JSON::Any }.should eq("legacy_duplicate:1")
  end
end
