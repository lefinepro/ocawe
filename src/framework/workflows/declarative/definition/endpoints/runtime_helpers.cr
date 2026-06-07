module Ocawe
  module Workflow
    class WorkflowDefinition
      def wait_for_event(event_name : String, resume_label : String? = nil) : self
        ensure_not_committed!

        waiter = WorkflowNode.new("wait-for-event-#{event_name}-#{@nodes.size}", NodeKind::Control) do |ctx|
          event = ctx.resume_data.try(&.["event_name"]?) || ctx.state["event_name"]?
          if event && event.raw == event_name
            WorkflowNodeResult.continue({"event_name" => JSON.parse(event_name.to_json)})
          else
            WorkflowNodeResult.suspend(
              {"reason" => JSON.parse("waiting for event #{event_name}".to_json)},
              resume_label || "event:#{event_name}",
            )
          end
        end

        @nodes << waiter
        self
      end

      def send_event(event_name : String, payload : AnyHash = {} of String => JSON::Any) : self
        ensure_not_committed!

        sender = WorkflowNode.new("send-event-#{event_name}-#{@nodes.size}", NodeKind::Control) do |_ctx|
          event_payload = {"event_name" => JSON.parse(event_name.to_json)}
          payload.each { |k, v| event_payload[k] = v }
          WorkflowNodeResult.continue(event_payload)
        end

        @nodes << sender
        self
      end

      def sleep(milliseconds : Int32) : self
        ensure_not_committed!
        sleeper = WorkflowNode.new("sleep-#{@nodes.size}", NodeKind::Control) do |_ctx|
          ::sleep(milliseconds.milliseconds)
          WorkflowNodeResult.continue
        end
        @nodes << sleeper
        self
      end

      def sleep_until(unix_time_seconds : Int64) : self
        ensure_not_committed!
        sleeper = WorkflowNode.new("sleep-until-#{@nodes.size}", NodeKind::Control) do |_ctx|
          now = Time.utc.to_unix
          remaining = unix_time_seconds - now
          ::sleep(remaining.seconds) if remaining > 0
          WorkflowNodeResult.continue
        end
        @nodes << sleeper
        self
      end

      def commit : self
        @committed = true
        self
      end

      def create_run(options : WorkflowRunOptions = WorkflowRunOptions.new) : WorkflowRunHandle
        run_id = options.run_id || "run_#{Time.utc.to_unix_ms}_#{Random.rand(100000)}"
        WorkflowRunHandle.new(self, run_id, options.resource_id)
      end

      def create_run_async(options : WorkflowRunOptions = WorkflowRunOptions.new) : WorkflowRunHandle
        create_run(options)
      end

    end
  end
end
