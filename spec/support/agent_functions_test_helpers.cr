module Ocawe
  module AgentFunctionHandlers
    extend self

    def test_provider_env(provider : String, input_data : Ocawe::Workflow::AnyHash) : Hash(String, String)
      ctx = Ocawe::Workflow::NodeContext.new(
        workflow_id: "spec-workflow",
        run_id: "spec-run",
        node_id: "spec-node",
        input_data: input_data,
        state: {} of String => JSON::Any,
      )
      provider_env(ctx, provider)
    end

    def test_apply_forgefed_merge_prompt_contract(prompt : String, input_data : Ocawe::Workflow::AnyHash) : String
      ctx = Ocawe::Workflow::NodeContext.new(
        workflow_id: "spec-workflow",
        run_id: "spec-run",
        node_id: "spec-node",
        input_data: input_data,
        state: {} of String => JSON::Any,
      )
      apply_forgefed_merge_prompt_contract(ctx, prompt)
    end

    def test_apply_agent_prompt_contracts(prompt : String, input_data : Ocawe::Workflow::AnyHash) : String
      ctx = Ocawe::Workflow::NodeContext.new(
        workflow_id: "spec-workflow",
        run_id: "spec-run",
        node_id: "spec-node",
        input_data: input_data,
        state: {} of String => JSON::Any,
      )
      apply_agent_prompt_contracts(ctx, prompt)
    end

    def test_apply_agent_prompt_contracts_with_state(
      prompt : String,
      input_data : Ocawe::Workflow::AnyHash,
      state : Ocawe::Workflow::AnyHash
    ) : String
      ctx = Ocawe::Workflow::NodeContext.new(
        workflow_id: "spec-workflow",
        run_id: "spec-run",
        node_id: "spec-node",
        input_data: input_data,
        state: state,
      )
      apply_agent_prompt_contracts(ctx, prompt)
    end
  end
end
