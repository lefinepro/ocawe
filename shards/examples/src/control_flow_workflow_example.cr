module CogniExamples
  module ControlFlowWorkflowExample
    extend self

    def build_branch_parallel_workflow : Cogni::Workflow::WorkflowDefinition
      seed = Cogni::Workflow::WorkflowNode.new("seed", Cogni::Workflow::NodeKind::Control) do |_ctx|
        Cogni::Workflow::WorkflowNodeResult.continue({
          "value" => JSON.parse("v1".to_json),
          "branch" => JSON.parse("true".to_json),
          "dowhile_runs" => JSON.parse(2_i64.to_json),
          "dountil_runs" => JSON.parse(2_i64.to_json),
          "foreach_ran" => JSON.parse(true.to_json),
        })
      end

      parallel_left = Cogni::Workflow::WorkflowNode.new("parallel-left", Cogni::Workflow::NodeKind::Control) do |_ctx|
        Cogni::Workflow::WorkflowNodeResult.continue({"left" => JSON.parse("ok".to_json)})
      end

      parallel_right = Cogni::Workflow::WorkflowNode.new("parallel-right", Cogni::Workflow::NodeKind::Control) do |_ctx|
        Cogni::Workflow::WorkflowNodeResult.continue({"right" => JSON.parse("ok".to_json)})
      end

      then_node = Cogni::Workflow::WorkflowNode.new("then-node", Cogni::Workflow::NodeKind::Control) do |_ctx|
        Cogni::Workflow::WorkflowNodeResult.continue({"then_ran" => JSON.parse(true.to_json)})
      end

      Cogni::Workflow.create_workflow("control-flow-branch-parallel", "Control-flow API example with schemas")
        .step(seed)
        .parallel([parallel_left, parallel_right])
        .step(then_node)
        .wait_for_event("deploy", "event:deploy")
        .send_event("deploy", {"source" => JSON.parse("example".to_json)})
        .commit
    end
  end
end
