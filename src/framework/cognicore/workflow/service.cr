module CogniCore
  module Workflow
    class Service
      def initialize(@engine : Engine)
      end

      def start_run(
        workflow_id : String,
        run_id : String? = nil,
        resource_id : String? = nil,
        input_data : AnyHash = {} of String => JSON::Any,
        request_context : AnyHash? = nil,
        output_options : WorkflowOutputOptions = WorkflowOutputOptions.new,
        runtime_context : AnyHash? = nil,
        trigger_data : AnyHash? = nil
      )
        run = @engine.create_run(workflow_id, WorkflowRunOptions.new(run_id, resource_id))
        result = run.start(
          input_data: input_data,
          request_context: request_context,
          output_options: output_options,
          runtime_context: runtime_context,
          trigger_data: trigger_data,
        )
        @engine.persist(run.get_current_run)
        result
      end

      def resume_run(
        workflow_id : String,
        run_id : String,
        resume_data : AnyHash = {} of String => JSON::Any,
        node : String | Array(String) | Nil = nil,
        request_context : AnyHash? = nil,
        output_options : WorkflowOutputOptions = WorkflowOutputOptions.new,
        runtime_context : AnyHash? = nil,
        trigger_data : AnyHash? = nil,
        wait_for_all_paths : Bool = false
      )
        run = hydrate_run(workflow_id, run_id)
        result = run.resume(
          resume_data: resume_data,
          node: node,
          request_context: request_context,
          output_options: output_options,
          runtime_context: runtime_context,
          trigger_data: trigger_data,
          wait_for_all_paths: wait_for_all_paths,
        )
        @engine.persist(run.get_current_run)
        result
      end

      def restart_run(workflow_id : String, run_id : String, request_context : AnyHash? = nil, trigger_data : AnyHash? = nil)
        run = hydrate_run(workflow_id, run_id)
        result = run.restart(request_context: request_context, trigger_data: trigger_data)
        @engine.persist(run.get_current_run)
        result
      end

      def cancel_run(workflow_id : String, run_id : String, request_context : AnyHash? = nil)
        run = hydrate_run(workflow_id, run_id)
        result = run.cancel(request_context: request_context)
        @engine.persist(run.get_current_run)
        result
      end

      def time_travel_run(
        workflow_id : String,
        run_id : String,
        node : String | Array(String),
        input_data : AnyHash? = nil,
        initial_state : AnyHash? = nil,
        resume_data : AnyHash? = nil,
        context : AnyHash? = nil,
        nested_nodes_context : AnyHash? = nil,
        request_context : AnyHash? = nil,
        output_options : WorkflowOutputOptions = WorkflowOutputOptions.new,
        trigger_data : AnyHash? = nil,
        runtime_context : AnyHash? = nil
      )
        run = hydrate_run(workflow_id, run_id)
        result = run.time_travel(
          node: node,
          input_data: input_data,
          initial_state: initial_state,
          resume_data: resume_data,
          context: context,
          nested_nodes_context: nested_nodes_context,
          request_context: request_context,
          output_options: output_options,
          trigger_data: trigger_data,
          runtime_context: runtime_context,
        )
        @engine.persist(run.get_current_run)
        result
      end

      def watch_run(
        workflow_id : String,
        run_id : String,
        input_data : AnyHash = {} of String => JSON::Any,
        output_options : WorkflowOutputOptions = WorkflowOutputOptions.new,
        request_context : AnyHash? = nil,
        trigger_data : AnyHash? = nil,
        runtime_context : AnyHash? = nil
      )
        run = hydrate_run(workflow_id, run_id)
        events = run.watch(
          input_data: input_data,
          output_options: output_options,
          request_context: request_context,
          trigger_data: trigger_data,
          runtime_context: runtime_context,
        )
        @engine.persist(run.get_current_run)
        events
      end

      def load_snapshot(workflow_id : String, run_id : String)
        @engine.load(workflow_id, run_id)
      end

      def list_runs(workflow_id : String? = nil, status : String? = nil)
        @engine.list_runs(workflow_id, status)
      end

      private def hydrate_run(workflow_id : String, run_id : String)
        definition = @engine.get(workflow_id)
        snapshot = @engine.load(workflow_id, run_id)
        run = definition.create_run(WorkflowRunOptions.new(run_id, snapshot.try(&.resource_id)))

        if snapshot
          run.restore_from_snapshot(snapshot)
        end

        run
      end
    end
  end
end
