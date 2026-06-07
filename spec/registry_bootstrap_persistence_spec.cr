require "./spec_helper"

describe "Ocawe::RegistryApi bootstrap persistence" do
  it "replays custom function registrations after reset_all!" do
    Ocawe::RegistryApi.reset_all!

    Ocawe::RegistryApi.register_function("persisted_runtime_fn") do |_ctx|
      {"status" => json_str("ok")}
    end

    Ocawe::RegistryApi.reset_all!

    workflow = Ocawe::Workflow.create_workflow("wf-persisted-function")
    workflow
      .step(Ocawe::NodeKind.new("persisted_runtime_fn"), id: "persisted_runtime_fn")
      .commit

    engine = Ocawe::Workflow::Engine.new
    engine.register(workflow)

    result = engine.create_run("wf-persisted-function").start
    result.status.should eq("success")
    result.state.not_nil!["status"].as_s.should eq("ok")
  end
end
