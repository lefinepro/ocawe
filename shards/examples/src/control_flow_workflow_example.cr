module CogniExamples
  module ControlFlowWorkflowExample
    extend self

    private def any_schema : CogniCore::Schema::Validator
      CogniCore::Schema::Types.any
    end

    private def object_schema(fields : Hash(String, CogniCore::Schema::Validator), strict : Bool = false) : CogniCore::Schema::Validator
      CogniCore::Schema::Types.object(fields, strict: strict)
    end

    # Programmatic example because branch/parallel/control methods are workflow API features,
    # while .acd.cr loader currently focuses on line directives.
    def build_branch_parallel_workflow : CogniCore::Workflow::WorkflowDefinition
      branch_true = CogniCore::Workflow::WorkflowNode.new(
        "branch-true",
        CogniCore::Workflow::NodeKind::Control,
        input_schema: any_schema,
        output_schema: object_schema({
          "branch" => CogniCore::Schema::Types.of(String),
        }, strict: false)
      ) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({
          "branch" => JSON.parse("true".to_json),
        })
      end

      branch_fallback = CogniCore::Workflow::WorkflowNode.new(
        "branch-fallback",
        CogniCore::Workflow::NodeKind::Control,
        input_schema: any_schema,
        output_schema: object_schema({
          "branch" => CogniCore::Schema::Types.of(String),
        }, strict: false)
      ) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({
          "branch" => JSON.parse("fallback".to_json),
        })
      end

      parallel_left = CogniCore::Workflow::WorkflowNode.new(
        "parallel-left",
        CogniCore::Workflow::NodeKind::Control,
        input_schema: any_schema,
        output_schema: object_schema({
          "left" => CogniCore::Schema::Types.of(String),
        }, strict: false)
      ) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({
          "left" => JSON.parse("ok".to_json),
        })
      end

      parallel_right = CogniCore::Workflow::WorkflowNode.new(
        "parallel-right",
        CogniCore::Workflow::NodeKind::Control,
        input_schema: any_schema,
        output_schema: object_schema({
          "right" => CogniCore::Schema::Types.of(String),
        }, strict: false)
      ) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({
          "right" => JSON.parse("ok".to_json),
        })
      end

      do_counter = 0
      until_counter = 0

      do_node = CogniCore::Workflow::WorkflowNode.new(
        "do-node",
        CogniCore::Workflow::NodeKind::Control,
        input_schema: any_schema,
        output_schema: object_schema({
          "dowhile_runs" => CogniCore::Schema::Types.of(Int64),
        }, strict: false)
      ) do |_ctx|
        do_counter += 1
        CogniCore::Workflow::WorkflowNodeResult.continue({
          "dowhile_runs" => JSON.parse(do_counter.to_i64.to_json),
        })
      end

      until_node = CogniCore::Workflow::WorkflowNode.new(
        "until-node",
        CogniCore::Workflow::NodeKind::Control,
        input_schema: any_schema,
        output_schema: object_schema({
          "dountil_runs" => CogniCore::Schema::Types.of(Int64),
        }, strict: false)
      ) do |_ctx|
        until_counter += 1
        CogniCore::Workflow::WorkflowNodeResult.continue({
          "dountil_runs" => JSON.parse(until_counter.to_i64.to_json),
        })
      end

      foreach_node = CogniCore::Workflow::WorkflowNode.new(
        "foreach-node",
        CogniCore::Workflow::NodeKind::Control,
        input_schema: any_schema,
        output_schema: object_schema({
          "foreach_ran" => CogniCore::Schema::Types.of(Bool),
        }, strict: false)
      ) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({
          "foreach_ran" => JSON.parse(true.to_json),
        })
      end

      then_node = CogniCore::Workflow::WorkflowNode.new(
        "then-node",
        CogniCore::Workflow::NodeKind::Control,
        input_schema: any_schema,
        output_schema: object_schema({
          "then_ran" => CogniCore::Schema::Types.of(Bool),
        }, strict: false)
      ) do |_ctx|
        CogniCore::Workflow::WorkflowNodeResult.continue({
          "then_ran" => JSON.parse(true.to_json),
        })
      end

      CogniCore::Workflow.create_workflow("control-flow-branch-parallel", "Control-flow API example with schemas")
        .map("seed") { |_ctx| {"value" => JSON.parse("v1".to_json)} }
        .branch([
          {->(ctx : CogniCore::Workflow::NodeContext) { ctx.input_data["value"]?.try(&.as_s?) == "v1" }, branch_true},
        ] of Tuple(CogniCore::Workflow::BranchCondition, CogniCore::Workflow::WorkflowNode), otherwise_node: branch_fallback)
        .parallel([parallel_left, parallel_right])
        .then(then_node)
        .sleep(0)
        .sleep_until(Time.utc.to_unix)
        .dowhile(do_node, ->(_ctx : CogniCore::Workflow::NodeContext) { do_counter < 2 })
        .dountil(until_node, ->(_ctx : CogniCore::Workflow::NodeContext) { until_counter >= 2 })
        .foreach(foreach_node)
        .wait_for_event("deploy", "event:deploy")
        .send_event("deploy", {"source" => JSON.parse("example".to_json)})
        .commit
    end
  end
end
