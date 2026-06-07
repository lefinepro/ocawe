module OcaweExamples
  module ControlFlowWorkflowExample
    extend self

    def build_branch_parallel_workflow : Ocawe::Workflow::WorkflowDefinition
      seed = Ocawe::Workflow::WorkflowNode.new("seed", Ocawe::Workflow::NodeKind::Control) do |_ctx|
        Ocawe::Workflow::WorkflowNodeResult.continue({
          "value" => JSON.parse("v1".to_json),
          "branch" => JSON.parse("true".to_json),
          "dowhile_runs" => JSON.parse(2_i64.to_json),
          "dountil_runs" => JSON.parse(2_i64.to_json),
          "foreach_ran" => JSON.parse(true.to_json),
        })
      end

      parallel_left = Ocawe::Workflow::WorkflowNode.new("parallel-left", Ocawe::Workflow::NodeKind::Control) do |_ctx|
        Ocawe::Workflow::WorkflowNodeResult.continue({"left" => JSON.parse("ok".to_json)})
      end

      parallel_right = Ocawe::Workflow::WorkflowNode.new("parallel-right", Ocawe::Workflow::NodeKind::Control) do |_ctx|
        Ocawe::Workflow::WorkflowNodeResult.continue({"right" => JSON.parse("ok".to_json)})
      end

      then_node = Ocawe::Workflow::WorkflowNode.new("then-node", Ocawe::Workflow::NodeKind::Control) do |_ctx|
        Ocawe::Workflow::WorkflowNodeResult.continue({"then_ran" => JSON.parse(true.to_json)})
      end

      Ocawe::Workflow.create_workflow("control-flow-branch-parallel", "Control-flow API example with schemas")
        .step(seed)
        .parallel([parallel_left, parallel_right])
        .step(then_node)
        .wait_for_event("deploy", "event:deploy")
        .send_event("deploy", {"source" => JSON.parse("example".to_json)})
        .commit
    end
  end
end
