module Cogni
  module Workflow
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
