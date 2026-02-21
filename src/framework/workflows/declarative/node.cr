require "../dsl/types"

module Cogni
  module Workflow
    struct NodeContext
      getter workflow_id : String
      getter run_id : String
      getter node_id : String
      getter input_data : AnyHash
      getter state : AnyHash
      getter init_data : AnyHash
      getter node_results : Hash(String, AnyHash)
      getter runtime_context : AnyHash?
      getter request_context : AnyHash?
      getter trigger_data : AnyHash?
      getter resume_data : AnyHash?

      def initialize(
        @workflow_id : String,
        @run_id : String,
        @node_id : String,
        @input_data : AnyHash,
        @state : AnyHash,
        @init_data : AnyHash = {} of String => JSON::Any,
        @node_results : Hash(String, AnyHash) = {} of String => AnyHash,
        @runtime_context : AnyHash? = nil,
        @request_context : AnyHash? = nil,
        @trigger_data : AnyHash? = nil,
        @resume_data : AnyHash? = nil
      )
      end

      def get_node_result(id : String) : AnyHash?
        @node_results[id]?
      end

      def get_step_result(id : String) : AnyHash?
        get_node_result(id)
      end

      def get_init_data : AnyHash
        @init_data
      end
    end

    class WorkflowNode
      getter id : String
      getter kind : NodeKind
      getter metadata : AnyHash

      def initialize(
        @id : String,
        @kind : NodeKind = NodeKind::Control,
        @metadata : AnyHash = {} of String => JSON::Any,
        @input_schema : Cogni::Workflows::DSL::Validator? = nil,
        @output_schema : Cogni::Workflows::DSL::Validator? = nil,
        &@executor : NodeContext -> WorkflowNodeResult
      )
      end

      def execute(ctx : NodeContext) : WorkflowNodeResult
        validate_input!(ctx)
        result = @executor.call(ctx)
        validate_output!(result)
        result
      rescue ex
        WorkflowNodeResult.fail(ex.message || "unknown node failure")
      end

      private def validate_input!(ctx : NodeContext)
        return unless schema = @input_schema
        payload = JSON.parse(ctx.input_data.to_json)
        schema.validate(payload, "$.input")
      end

      private def validate_output!(result : WorkflowNodeResult)
        return unless schema = @output_schema
        return unless result.action == NodeAction::Continue.to_s.downcase
        payload = JSON.parse((result.data || {} of String => JSON::Any).to_json)
        schema.validate(payload, "$.output")
      end
    end
  end
end
