module Ocawe
  module Workflow
    class WorkflowDefinition
      getter id : String
      getter description : String?
      getter nodes : Array(WorkflowNode)
      getter default_model : String?
      getter default_logger : AnyHash?
      getter node_loggers : Hash(String, AnyHash)
      getter default_workspace : AnyHash?
      getter node_workspaces : Hash(String, AnyHash)

      def initialize(@id : String, @description : String? = nil)
        @nodes = [] of WorkflowNode
        @committed = false
        @default_model = nil
        @default_logger = nil.as(AnyHash?)
        @node_loggers = {} of String => AnyHash
        @default_workspace = nil.as(AnyHash?)
        @node_workspaces = {} of String => AnyHash
        @pending_node_workspace = nil.as(AnyHash?)
      end

      def logger(config : AnyHash) : self
        ensure_not_committed!
        @default_logger = config.dup
        self
      end

      def apply_logger_to_last_node(config : AnyHash) : self
        ensure_not_committed!
        raise "cannot apply logger without nodes" if @nodes.empty?

        normalized = JSON.parse(config.to_json).as_h
        node = @nodes.last
        node.metadata["logger"] = JSON.parse(normalized.to_json)
        @node_loggers[node.id] = normalized
        self
      end

      def logger_for_node(node_id : String) : AnyHash?
        workflow_logger = @default_logger
        node_logger = @node_loggers[node_id]?

        return nil unless workflow_logger || node_logger
        merged = (workflow_logger || ({} of String => JSON::Any)).dup
        if node_logger
          node_logger.each { |k, v| merged[k] = v }
        end
        merged
      end

      def workspace(config : AnyHash) : self
        ensure_not_committed!
        @default_workspace = normalize_hash(config)
        self
      end

      def workspace_next(config : AnyHash) : self
        ensure_not_committed!
        @pending_node_workspace = normalize_hash(config)
        self
      end

      def apply_workspace_to_last_node(config : AnyHash) : self
        ensure_not_committed!
        raise "cannot apply workspace without nodes" if @nodes.empty?

        node = @nodes.last
        resolved = resolve_workspace_for_node(node, normalize_hash(config)) || ({} of String => JSON::Any)
        raise "workspace config cannot be empty" if resolved.empty?
        node.metadata["workspace"] = JSON.parse(resolved.to_json)
        @node_workspaces[node.id] = resolved
        self
      end

    end
  end
end
