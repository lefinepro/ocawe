require "./spec_helper"

describe "function registry" do
  before_each do
    Ocawe::Workflow.reset_function_registry!
  end

  it "registers a system function from a typed FunctionHandler proc" do
    handler : Ocawe::Workflow::FunctionHandler = ->(ctx : Ocawe::Workflow::NodeContext) : Ocawe::Workflow::RunnableResult do
      Ocawe::Workflow::AgentResult.new(
        agent_type: "function",
        content: "hello #{ctx.node_id}",
      )
    end

    Ocawe::RegistryApi.register_system_function("typed_handler", &handler)

    ctx = Ocawe::Workflow::NodeContext.new(
      workflow_id: "wf-test",
      run_id: "run-test",
      node_id: "node-1",
      input_data: {} of String => JSON::Any,
      state: {} of String => JSON::Any,
    )

    result = Ocawe::RegistryApi.call_function("typed_handler", ctx)
    result["content"].as_s.should eq("hello node-1")
    result["agent_type"].as_s.should eq("function")
  end

  it "allows functions to return a hash payload directly" do
    Ocawe::RegistryApi.register_function("hash_handler") do |ctx|
      {
        "node" => json_str(ctx.node_id),
      } of String => JSON::Any
    end

    ctx = Ocawe::Workflow::NodeContext.new(
      workflow_id: "wf-test",
      run_id: "run-test",
      node_id: "node-2",
      input_data: {} of String => JSON::Any,
      state: {} of String => JSON::Any,
    )

    result = Ocawe::RegistryApi.call_function("hash_handler", ctx)
    result["node"].as_s.should eq("node-2")
  end
end
