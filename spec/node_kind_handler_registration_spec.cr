require "./spec_helper"

describe "custom node kinds and resource registrations" do
  it "executes custom node kind from declarative API" do
    Ocawe::Workflow.reset_node_kind_registry!
    Ocawe::RegistryApi.node_kind("crystal_native") do |_ctx, attributes|
      {
        "kind" => json_str("ok"),
        "value" => attributes["value"]? || json_str("missing"),
      }
    end

    workflow = Ocawe::Workflow.create_workflow("wf-custom-kind")
    workflow
      .step(Ocawe::NodeKind.new("crystal_native", {
        "value" => json_str("from-attributes"),
      }))
      .commit

    engine = Ocawe::Workflow::Engine.new
    engine.register(workflow)

    result = engine.create_run("wf-custom-kind").start
    result.status.should eq("success")
    result.state.not_nil!["kind"].as_s.should eq("ok")
    result.state.not_nil!["value"].as_s.should eq("from-attributes")
  end

  it "registers resources from a node kind handler" do
    Ocawe::Workflow.reset_node_kind_registry!
    Ocawe::Workflow.reset_resource_registry!

    Ocawe::RegistryApi.node_kind("bootstrap") do |ctx, _parameters|
      Ocawe::RegistryApi.resource("resource_ping") do |_resource_ctx, payload|
        {
          "resource_task" => json_str(payload["task"]?.try(&.as_s?) || "none"),
        }
      end

      resource_value = Ocawe::Workflow.resource_registry.call("resource_ping", ctx, {
        "task" => json_str("beta"),
      })

      {
        "registered_from" => json_str(ctx.node_id),
        "resource_value" => JSON.parse(resource_value.to_json),
      }
    end

    workflow = Ocawe::Workflow.create_workflow("wf-handler-registration")
    workflow
      .step(Ocawe::NodeKind.new("bootstrap"), id: "bootstrap-node")
      .commit

    engine = Ocawe::Workflow::Engine.new
    engine.register(workflow)

    result = engine.create_run("wf-handler-registration").start

    result.status.should eq("success")
    result.state.not_nil!["registered_from"].as_s.should eq("bootstrap-node")
    result.state.not_nil!["resource_value"].as_h["resource_task"].as_s.should eq("beta")
  end
end
