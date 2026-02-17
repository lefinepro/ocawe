module Cogni
  module Workflows
    module Declarative
    module SnapshotStore
      abstract def persist(snapshot : WorkflowRunSnapshot)
      abstract def load(workflow_id : String, run_id : String) : WorkflowRunSnapshot?
      abstract def list(workflow_id : String? = nil, status : String? = nil) : Array(WorkflowRunSnapshot)
    end

    class InMemorySnapshotStore
      include SnapshotStore

      def initialize
        @snapshots = {} of String => WorkflowRunSnapshot
      end

      def persist(snapshot : WorkflowRunSnapshot)
        @snapshots[key(snapshot.workflow_id, snapshot.run_id)] = snapshot
      end

      def load(workflow_id : String, run_id : String) : WorkflowRunSnapshot?
        @snapshots[key(workflow_id, run_id)]?
      end

      def list(workflow_id : String? = nil, status : String? = nil) : Array(WorkflowRunSnapshot)
        @snapshots.values.select do |snapshot|
          workflow_match = workflow_id.nil? || snapshot.workflow_id == workflow_id
          status_match = status.nil? || snapshot.status == status
          workflow_match && status_match
        end
      end

      private def key(workflow_id : String, run_id : String)
        "#{workflow_id}:#{run_id}"
      end
    end
  end
  end
end
