module Cogni
  module Workflow
    class WorkflowRunHandle
      private def node_input_for(node : WorkflowNode, previous_node_id : String?, previous_node_result : AnyHash?) : AnyHash
        if node.kind == NodeKind::Agent || node.kind == NodeKind::Exec || node.kind == NodeKind::Custom
          input_payload = if previous_node_result
                            JSON.parse(previous_node_result.to_json)
                          elsif explicit = @init_data["input"]?
                            JSON.parse(explicit.to_json)
                          else
                            JSON.parse(@init_data.to_json)
                          end
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

          if node.kind == NodeKind::Exec || node.kind == NodeKind::Custom
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
  end
end
