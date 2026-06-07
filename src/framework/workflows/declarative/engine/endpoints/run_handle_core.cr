module Ocawe
  module Workflow
    class WorkflowRunHandle
      getter run_id : String
      getter workflow_id : String
      getter resource_id : String?
      @state : AnyHash
      @init_data : AnyHash
      @node_results : Hash(String, AnyHash)

      def initialize(@definition : WorkflowDefinition, @run_id : String, @resource_id : String?)
        @workflow_id = @definition.id
        @status = RunStatus::Running
        @node_index = 0
        @state = {} of String => JSON::Any
        @init_data = {} of String => JSON::Any
        @node_results = {} of String => AnyHash
        @output = nil.as(AnyHash?)
        @resume_labels = [] of String
        @suspend_payload = nil.as(AnyHash?)
        @error = nil.as(WorkflowError?)
      end

      def start(
        input_data : AnyHash = {} of String => JSON::Any,
        resources : AnyHash? = nil,
        runtime_context : AnyHash? = nil,
        output_options : WorkflowOutputOptions = WorkflowOutputOptions.new,
        request_context : AnyHash? = nil,
        trigger_data : AnyHash? = nil,
        snapshot : WorkflowRunSnapshot? = nil
      ) : WorkflowRunResult
        @node_index = snapshot.try(&.node_index) || 0
        @init_data = snapshot.try(&.init_data) || input_data.dup
        @node_results = snapshot.try(&.node_results) || {} of String => AnyHash
        execute_from_current(
          input_data: input_data,
          runtime_context: runtime_context,
          output_options: output_options,
          request_context: request_context,
          trigger_data: trigger_data,
          resources: resources,
          resume_data: nil,
          explicit_node: nil,
        )
      end

      def resume(
        resume_data : AnyHash = {} of String => JSON::Any,
        resources : AnyHash? = nil,
        node : String | Array(String) | Nil = nil,
        runtime_context : AnyHash? = nil,
        output_options : WorkflowOutputOptions = WorkflowOutputOptions.new,
        request_context : AnyHash? = nil,
        trigger_data : AnyHash? = nil,
        snapshot : WorkflowRunSnapshot? = nil,
        wait_for_all_paths : Bool = false
      ) : WorkflowRunResult
        _ = wait_for_all_paths
        if snapshot
          @node_index = snapshot.node_index
          @state = snapshot.state || @state
          @init_data = snapshot.init_data || @init_data
          @node_results = snapshot.node_results || @node_results
        end

        explicit = case node
        when String
          node
        when Array(String)
          node.first?
        else
          nil
        end

        execute_from_current(
          input_data: @state,
          runtime_context: runtime_context,
          output_options: output_options,
          request_context: request_context,
          trigger_data: trigger_data,
          resources: resources,
          resume_data: resume_data,
          explicit_node: explicit,
        )
      end

      def watch(
        input_data : AnyHash = {} of String => JSON::Any,
        output_options : WorkflowOutputOptions = WorkflowOutputOptions.new,
        request_context : AnyHash? = nil,
        trigger_data : AnyHash? = nil,
        runtime_context : AnyHash? = nil
      ) : Array(WorkflowStreamEvent)
        events = [] of WorkflowStreamEvent
        events << event(EventType::RunStarted, nil, "run started")

        result = start(
          input_data: input_data,
          runtime_context: runtime_context,
          output_options: output_options,
          request_context: request_context,
          trigger_data: trigger_data,
        )

        if result.status == RunStatus::Success.to_s.downcase
          events << event(EventType::RunCompleted, nil, "run completed")
        elsif result.status == RunStatus::Suspended.to_s.downcase
          events << event(EventType::RunSuspended, nil, "run suspended")
        elsif result.status == RunStatus::Cancelled.to_s.downcase
          events << event(EventType::RunCancelled, nil, "run cancelled")
        else
          events << event(EventType::RunFailed, nil, "run failed")
        end

        events
      end

      def stream(
        input_data : AnyHash = {} of String => JSON::Any,
        output_options : WorkflowOutputOptions = WorkflowOutputOptions.new,
        request_context : AnyHash? = nil,
        trigger_data : AnyHash? = nil,
        runtime_context : AnyHash? = nil
      ) : Array(WorkflowStreamEvent)
        watch(
          input_data: input_data,
          output_options: output_options,
          request_context: request_context,
          trigger_data: trigger_data,
          runtime_context: runtime_context,
        )
      end

      def restart(
        request_context : AnyHash? = nil,
        trigger_data : AnyHash? = nil,
        snapshot : WorkflowRunSnapshot? = nil
      ) : WorkflowRunResult
        @status = RunStatus::Running
        @node_index = 0
        @state = snapshot.try(&.state) || {} of String => JSON::Any
        @init_data = snapshot.try(&.init_data) || {} of String => JSON::Any
        @node_results = snapshot.try(&.node_results) || {} of String => AnyHash
        @output = nil
        @resume_labels.clear
        @suspend_payload = nil
        @error = nil

        start(
          input_data: @state,
          request_context: request_context,
          trigger_data: trigger_data,
          snapshot: snapshot,
        )
      end

      def cancel(request_context : AnyHash? = nil)
        _ = request_context
        @status = RunStatus::Cancelled
        current_result
      end

      def time_travel(
        node : String | Array(String),
        input_data : AnyHash? = nil,
        initial_state : AnyHash? = nil,
        resume_data : AnyHash? = nil,
        context : AnyHash? = nil,
        nested_nodes_context : AnyHash? = nil,
        output_options : WorkflowOutputOptions = WorkflowOutputOptions.new,
        request_context : AnyHash? = nil,
        trigger_data : AnyHash? = nil,
        snapshot : WorkflowRunSnapshot? = nil,
        runtime_context : AnyHash? = nil
      ) : WorkflowRunResult
        _ = nested_nodes_context
        _ = context
        if snapshot
          @state = snapshot.state || @state
          @init_data = snapshot.init_data || @init_data
          @node_results = snapshot.node_results || @node_results
        end
        @state = initial_state if initial_state
        @state = input_data if input_data

        target = case node
                 when String
                   node
                 when Array(String)
                   node.first? || raise "time_travel requires at least one node"
                 end

        idx = @definition.nodes.index { |n| n.id == target }
        raise "unknown node for time_travel: #{target}" unless idx

        @node_index = idx
        @status = RunStatus::Running

        execute_from_current(
          input_data: @state,
          runtime_context: runtime_context,
          output_options: output_options,
          request_context: request_context,
          trigger_data: trigger_data,
          resources: nil,
          resume_data: resume_data,
          explicit_node: target,
        )
      end
    end
  end
end
