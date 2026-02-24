module Cogni
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

      def get_result : WorkflowRunResult
        current_result
      end

      def get_current_run : WorkflowRunSnapshot
        WorkflowRunSnapshot.new(
          workflow_id: @workflow_id,
          run_id: @run_id,
          status: @status.to_s.downcase,
          state: @state,
          output: @output,
          init_data: @init_data,
          node_results: @node_results,
          node_index: @node_index,
          resume_labels: @resume_labels.dup,
          suspend_payload: @suspend_payload,
          error: @error,
          resource_id: @resource_id,
          updated_at: Time.utc.to_s,
        )
      end

      def restore_from_snapshot(snapshot : WorkflowRunSnapshot)
        @status = parse_status(snapshot.status)
        @node_index = snapshot.node_index
        @state = snapshot.state || {} of String => JSON::Any
        @init_data = snapshot.init_data || {} of String => JSON::Any
        @node_results = snapshot.node_results || {} of String => AnyHash
        @output = snapshot.output
        @resume_labels = snapshot.resume_labels || [] of String
        @suspend_payload = snapshot.suspend_payload
        @error = snapshot.error
      end

      private def execute_from_current(
        input_data : AnyHash,
        runtime_context : AnyHash?,
        output_options : WorkflowOutputOptions,
        request_context : AnyHash?,
        trigger_data : AnyHash?,
        resources : AnyHash?,
        resume_data : AnyHash?,
        explicit_node : String?
      ) : WorkflowRunResult
        runtime_logger = Cogni::Logging::WorkflowLogger.new(@workflow_id, @run_id)
        runtime_logger.run_started(@definition.default_logger)
        @status = RunStatus::Running
        @state = input_data.dup
        if workflow_model = @definition.default_model
          @state["workflow_model"] = JSON.parse(workflow_model.to_json) unless @state["workflow_model"]?
        end
        @init_data = input_data.dup if @init_data.empty?
        if resources
          existing_resources = @state["resources"]?.try(&.as_h?) || {} of String => JSON::Any
          merged_resources = existing_resources.dup
          resources.each { |k, v| merged_resources[k] = v }
          @state["resources"] = JSON.parse(merged_resources.to_json)
        end
        @resume_labels.clear
        @suspend_payload = nil

        if explicit_node
          idx = @definition.nodes.index { |n| n.id == explicit_node }
          @node_index = idx || @node_index
        end

        previous_node_id = nil.as(String?)
        previous_node_result = nil.as(AnyHash?)

        while @node_index < @definition.nodes.size
          node = @definition.nodes[@node_index]
          node_logger_config = @definition.logger_for_node(node.id)
          runtime_logger.node_started(node.id, node_logger_config)
          node_input_data = node_input_for(node, previous_node_id, previous_node_result)
          ctx = NodeContext.new(
            workflow_id: @workflow_id,
            run_id: @run_id,
            node_id: node.id,
            input_data: node_input_data,
            state: @state,
            init_data: @init_data,
            node_results: @node_results,
            runtime_context: runtime_context,
            request_context: request_context,
            trigger_data: trigger_data,
            resume_data: resume_data,
          )

          workspace = node.metadata["workspace"]?.try(&.as_h?)
          Cogni::Workflow.workspace_registry.emit("before_node", ctx, workspace.not_nil!) if workspace
          result = node.execute(ctx)
          if workspace
            event_name = result.action == NodeAction::Fail.to_s.downcase ? "on_error" : "after_node"
            Cogni::Workflow.workspace_registry.emit(event_name, ctx, workspace)
          end

          case result.action
          when NodeAction::Continue.to_s.downcase
            if data = result.data
              @node_results[node.id] = data
              data.each { |k, v| @state[k] = v }
              previous_node_result = data
            end
            runtime_logger.node_completed(node.id, node_logger_config)
            previous_node_id = node.id
            @node_index += 1
          when NodeAction::Suspend.to_s.downcase
            @status = RunStatus::Suspended
            @suspend_payload = result.suspend_payload || {} of String => JSON::Any
            labels = result.resume_labels || [] of String
            labels.each { |label| @resume_labels << label unless @resume_labels.includes?(label) }
            runtime_logger.run_suspended(@definition.default_logger)
            return current_result(output_options)
          else
            @status = RunStatus::Failed
            @error = result.error || WorkflowError.new("workflow_error", "workflow node failed")
            runtime_logger.node_failed(node.id, node_logger_config, @error.try(&.message))
            runtime_logger.run_failed(@definition.default_logger, @error.try(&.message))
            return current_result(output_options)
          end
        end

        @status = RunStatus::Success
        @output = @state.dup
        runtime_logger.run_completed(@definition.default_logger)
        current_result(output_options)
      end

      private def node_input_for(node : WorkflowNode, previous_node_id : String?, previous_node_result : AnyHash?) : AnyHash
        if node.kind == NodeKind::Agent || node.kind == NodeKind::Run || node.kind == NodeKind::Custom
          input_payload = previous_node_result ? JSON.parse(previous_node_result.to_json) : JSON.parse(@init_data.to_json)
          context = {
            "workflow_id" => JSON.parse(@workflow_id.to_json),
            "run_id" => JSON.parse(@run_id.to_json),
            "previous_node_id" => previous_node_id ? JSON.parse(previous_node_id.to_json) : JSON.parse("null"),
            "state" => JSON.parse(@state.to_json),
          } of String => JSON::Any

          envelope = {
            "input" => input_payload,
            "context" => JSON.parse(context.to_json),
          } of String => JSON::Any
          if workspace = node.metadata["workspace"]?.try(&.as_h?)
            envelope["workspace"] = JSON.parse(workspace.to_json)
          end

          if node.kind == NodeKind::Run || node.kind == NodeKind::Custom
            if params = node.metadata["params"]?
              if flat = params.as_h?
                flat.each do |k, v|
                  envelope[k] = JSON.parse(v.to_json)
                end
              end
            end
            if node_kind_parameters = node.metadata["parameters"]?
              if flat = node_kind_parameters.as_h?
                flat.each do |k, v|
                  envelope[k] = JSON.parse(v.to_json)
                end
              end
            end
          end

          return envelope
        end

        @state
      end

      private def current_result(output_options : WorkflowOutputOptions = WorkflowOutputOptions.new)
        WorkflowRunResult.new(
          run_id: @run_id,
          workflow_id: @workflow_id,
          status: @status.to_s.downcase,
          output: @output,
          state: output_options.include_state ? @state : nil,
          resume_labels: output_options.include_resume_labels ? @resume_labels.dup : nil,
          suspend_payload: @suspend_payload,
          error: @error,
        )
      end

      private def event(type : EventType, node_id : String?, message : String)
        WorkflowStreamEvent.new(
          type: type.to_s,
          run_id: @run_id,
          workflow_id: @workflow_id,
          status: @status.to_s.downcase,
          node_id: node_id,
          message: message,
        )
      end

      private def parse_status(status : String)
        case status
        when RunStatus::Success.to_s.downcase
          RunStatus::Success
        when RunStatus::Failed.to_s.downcase
          RunStatus::Failed
        when RunStatus::Suspended.to_s.downcase
          RunStatus::Suspended
        when RunStatus::Cancelled.to_s.downcase
          RunStatus::Cancelled
        else
          RunStatus::Running
        end
      end
    end

    class Engine
      getter store : SnapshotStore

      def initialize(@store : SnapshotStore = InMemorySnapshotStore.new)
        @workflows = {} of String => WorkflowDefinition
      end

      def register(workflow : WorkflowDefinition)
        @workflows[workflow.id] = workflow
      end

      def get(workflow_id : String) : WorkflowDefinition
        @workflows[workflow_id]? || raise "unknown workflow: #{workflow_id}"
      end

      def create_run(workflow_id : String, options : WorkflowRunOptions = WorkflowRunOptions.new) : WorkflowRunHandle
        get(workflow_id).create_run(options)
      end

      def persist(snapshot : WorkflowRunSnapshot)
        @store.persist(snapshot)
      end

      def load(workflow_id : String, run_id : String)
        @store.load(workflow_id, run_id)
      end

      def list_runs(workflow_id : String? = nil, status : String? = nil)
        @store.list(workflow_id, status)
      end
    end
  end
end
