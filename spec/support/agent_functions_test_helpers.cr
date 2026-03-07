module Cogni
  module AgentFunctionHandlers
    extend self

    def test_provider_env(provider : String, input_data : Cogni::Workflow::AnyHash) : Hash(String, String)
      ctx = Cogni::Workflow::NodeContext.new(
        workflow_id: "spec-workflow",
        run_id: "spec-run",
        node_id: "spec-node",
        input_data: input_data,
        state: {} of String => JSON::Any,
      )
      provider_env(ctx, provider)
    end
  end
end
