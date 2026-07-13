module Ocawe
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
        explicit_node : String?,
      ) : WorkflowRunResult
        run_started_at = Ocawe::Utils::TimeCompat.monotonic
        telemetry_run_status = "running"
        run_span = Ocawe::Telemetry.start_span(
          "workflow.run",
          {
            "workflow.id"     => @workflow_id,
            "workflow.run_id" => @run_id,
          } of String => Ocawe::Telemetry::AttributeValue
        )
        runtime_logger = Ocawe::Logging::WorkflowLogger.new(@workflow_id, @run_id)
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
          node_started_at = Ocawe::Utils::TimeCompat.monotonic
          node_span = Ocawe::Telemetry.start_span(
            "workflow.node",
            {
              "workflow.id"        => @workflow_id,
              "workflow.run_id"    => @run_id,
              "workflow.node_id"   => node.id,
              "workflow.node_kind" => node.kind.to_s.downcase,
            } of String => Ocawe::Telemetry::AttributeValue
          )
          node_telemetry_status = "running"
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
          Ocawe::Workflow.workspace_registry.emit("before_node", ctx, workspace.not_nil!) if workspace
          result = begin
            node.execute(ctx)
          rescue ex
            node_telemetry_status = "error"
            record_node_telemetry(node, node_span, node_started_at, node_telemetry_status, ex.message || ex.class.name)
            raise ex
          end

          case result.action
          when NodeAction::Continue.to_s.downcase
            node_telemetry_status = "success"
            if workspace
              Ocawe::Workflow.workspace_registry.emit("after_node", ctx, workspace)
            end
            if data = result.data
              enriched = data.dup
              enriched["step"] = JSON.parse(node.id.to_json)
              @node_results[node.id] = enriched
              data.each { |k, v| @state[k] = v }
              previous_node_result = data
            end
            runtime_logger.node_completed(node.id, node_logger_config)
            record_node_telemetry(node, node_span, node_started_at, node_telemetry_status)
            previous_node_id = node.id
            @node_index += 1
          when NodeAction::Suspend.to_s.downcase
            node_telemetry_status = "suspended"
            if workspace
              Ocawe::Workflow.workspace_registry.emit("after_node", ctx, workspace)
            end
            @status = RunStatus::Suspended
            telemetry_run_status = "suspended"
            @suspend_payload = result.suspend_payload || {} of String => JSON::Any
            labels = result.resume_labels || [] of String
            labels.each { |label| @resume_labels << label unless @resume_labels.includes?(label) }
            runtime_logger.run_suspended(@definition.default_logger)
            record_node_telemetry(node, node_span, node_started_at, node_telemetry_status)
            return current_result(output_options)
          else
            node_telemetry_status = "error"
            if workspace
              Ocawe::Workflow.workspace_registry.emit("on_error", ctx, workspace)
            end
            @status = RunStatus::Failed
            telemetry_run_status = "failed"
            @error = result.error || WorkflowError.new("workflow_error", "workflow node failed")
            runtime_logger.node_failed(node.id, node_logger_config, @error.try(&.message))
            runtime_logger.run_failed(@definition.default_logger, @error.try(&.message))
            record_node_telemetry(node, node_span, node_started_at, node_telemetry_status, @error.try(&.message))
            Ocawe::Telemetry.log(
              "error",
              @error.try(&.message) || "workflow node failed",
              {
                "event.name"       => "workflow.node.failed",
                "workflow.id"      => @workflow_id,
                "workflow.run_id"  => @run_id,
                "workflow.node_id" => node.id,
              } of String => Ocawe::Telemetry::AttributeValue
            )
            return current_result(output_options)
          end
        end

        @status = RunStatus::Success
        telemetry_run_status = "success"
        @output = build_output_from_state
        runtime_logger.run_completed(@definition.default_logger)
        current_result(output_options)
      rescue ex
        telemetry_run_status = "error"
        Ocawe::Telemetry.log(
          "error",
          ex.message || ex.class.name,
          {
            "event.name"      => "workflow.run.exception",
            "workflow.id"     => @workflow_id,
            "workflow.run_id" => @run_id,
          } of String => Ocawe::Telemetry::AttributeValue
        )
        raise ex
      ensure
        finalized_run_status = telemetry_run_status || "unknown"
        duration_ms = Ocawe::Utils::TimeCompat.elapsed_milliseconds(run_started_at.not_nil!)
        metric_attrs = {
          "workflow.id"     => @workflow_id,
          "workflow.run_id" => @run_id,
          "workflow.status" => finalized_run_status,
        } of String => Ocawe::Telemetry::AttributeValue
        Ocawe::Telemetry.increment("workflow.run.count", attributes: metric_attrs)
        Ocawe::Telemetry.histogram("workflow.run.duration_ms", duration_ms, "ms", metric_attrs)
        Ocawe::Telemetry.finish_span(
          run_span,
          status: finalized_run_status,
          error: finalized_run_status == "failed" || finalized_run_status == "error" ? @error.try(&.message) || "workflow run failed" : nil,
          attributes: {"workflow.status" => finalized_run_status} of String => Ocawe::Telemetry::AttributeValue
        )
      end

      private def record_node_telemetry(
        node : WorkflowNode,
        node_span : OpenTelemetry::Span?,
        node_started_at,
        status : String,
        error : String? = nil,
      ) : Nil
        duration_ms = Ocawe::Utils::TimeCompat.elapsed_milliseconds(node_started_at)
        metric_attrs = {
          "workflow.id"        => @workflow_id,
          "workflow.node_id"   => node.id,
          "workflow.node_kind" => node.kind.to_s.downcase,
          "workflow.status"    => status,
        } of String => Ocawe::Telemetry::AttributeValue
        Ocawe::Telemetry.increment("workflow.node.execution.count", attributes: metric_attrs)
        Ocawe::Telemetry.histogram("workflow.node.execution.duration_ms", duration_ms, "ms", metric_attrs)
        Ocawe::Telemetry.finish_span(
          node_span,
          status: status,
          error: error,
          attributes: {"workflow.status" => status} of String => Ocawe::Telemetry::AttributeValue
        )
      end
    end
  end
end
