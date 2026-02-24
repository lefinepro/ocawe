module Cogni
  module Workflow
    class WorkflowRunHandle
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
    end
  end
end
