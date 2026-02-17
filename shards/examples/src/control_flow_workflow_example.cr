module CogniExamples
  module ControlFlowWorkflowExample
    extend self

    def build_branch_parallel_workflow : CogniCore::Workflow::WorkflowDefinition
      seed = CogniCore::Workflow::WorkflowNode.new("seed", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({
          "value" => JSON.parse("v1".to_json),
          "branch" => JSON.parse("true".to_json),
          "dowhile_runs" => JSON.parse(2_i64.to_json),
          "dountil_runs" => JSON.parse(2_i64.to_json),
          "foreach_ran" => JSON.parse(true.to_json),
        })
      end

      parallel_left = CogniCore::Workflow::WorkflowNode.new("parallel-left", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"left" => JSON.parse("ok".to_json)})
      end

      parallel_right = CogniCore::Workflow::WorkflowNode.new("parallel-right", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"right" => JSON.parse("ok".to_json)})
      end

      then_node = CogniCore::Workflow::WorkflowNode.new("then-node", CogniCore::Workflow::NodeKind::Control) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({"then_ran" => JSON.parse(true.to_json)})
      end

      CogniCore::Workflow.create_workflow("control-flow-branch-parallel", "Control-flow API example with schemas")
        .then(seed)
        .parallel([parallel_left, parallel_right])
        .then(then_node)
        .wait_for_event("deploy", "event:deploy")
        .send_event("deploy", {"source" => JSON.parse("example".to_json)})
        .commit
    end
  end
end
