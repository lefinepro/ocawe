module Ocawe
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
            if attributes = node.metadata["attributes"]?
              if flat = attributes.as_h?
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

      private def build_output_from_state : AnyHash
        output = @state.dup
        
        # If workflow has output_type, format output accordingly
        if output_type = @definition.output_type
          case output_type
          when "Api::Federation::Outbox"
            # Format as ActivityPub Outbox response
            activities = extract_federation_activities_from_state
            output = {
              "@context" => JSON.parse("https://www.w3.org/ns/activitystreams".to_json),
              "type" => JSON.parse("OrderedCollection".to_json),
              "totalItems" => JSON.parse(activities.size.to_json),
              "orderedItems" => JSON.parse(activities.to_json),
            } of String => JSON::Any
          when "Api::Federation::Inbox"
            # Format as ActivityPub Inbox response
            activities = extract_federation_activities_from_state
            output = {
              "@context" => JSON.parse("https://www.w3.org/ns/activitystreams".to_json),
              "type" => JSON.parse("OrderedCollection".to_json),
              "totalItems" => JSON.parse(activities.size.to_json),
              "orderedItems" => JSON.parse(activities.to_json),
            } of String => JSON::Any
          when "Api::OpenResponses::Response"
            # Format as OpenResponses
            output = format_openresponses_output(output)
          when "Api::ChatCompletionAPI::Response"
            # Format as ChatCompletion
            output = format_chatcompletion_output(output)
          end
        end
        
        output
      end
      
      private def extract_federation_activities_from_state : Array(Hash(String, JSON::Any))
        # Extract activities from state (e.g., from follow node results)
        activities = [] of Hash(String, JSON::Any)
        
        # Check for follow_records in state
        if follow_records = @state["follow_records"]?.try(&.as_a?)
          follow_records.each do |record|
            if hash = record.as_h?
              activities << hash
            end
          end
        end
        
        # Check for messages from outbox polling
        if messages = @state["messages"]?.try(&.as_a?)
          messages.each do |msg|
            if hash = msg.as_h?
              activities << hash
            end
          end
        end
        
        activities
      end
      
      private def format_openresponses_output(state : AnyHash) : AnyHash
        {
          "id" => JSON.parse(@run_id.to_json),
          "object" => JSON.parse("response".to_json),
          "created_at" => JSON.parse(Time.utc.to_unix.to_json),
          "status" => JSON.parse("completed".to_json),
          "model" => JSON.parse((state["model"]?.try(&.as_s?) || "unknown").to_json),
          "output" => JSON.parse((state["output"]?.try(&.as_a?) || [] of Hash(String, JSON::Any)).to_json),
        } of String => JSON::Any
      end
      
      private def format_chatcompletion_output(state : AnyHash) : AnyHash
        {
          "id" => JSON.parse(@run_id.to_json),
          "object" => JSON.parse("chat.completion".to_json),
          "created" => JSON.parse(Time.utc.to_unix.to_json),
          "model" => JSON.parse((state["model"]?.try(&.as_s?) || "unknown").to_json),
          "choices" => JSON.parse((state["choices"]?.try(&.as_a?) || [] of Hash(String, JSON::Any)).to_json),
        } of String => JSON::Any
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
        when RunStatus::Running.to_s.downcase
          RunStatus::Running
        else
          raise "invalid run status: #{status}"
        end
      end
    end
  end
end
