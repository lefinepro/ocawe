module Cogni
  module Workflow
    class WorkflowDefinition
      getter id : String
      getter description : String?
      getter nodes : Array(WorkflowNode)
      getter default_model : String?
      getter default_skills : Array(String)
      getter default_tools : Array(String)
      getter default_logger : AnyHash?
      getter node_loggers : Hash(String, AnyHash)
      getter default_workspace : AnyHash?
      getter node_workspaces : Hash(String, AnyHash)

      def initialize(@id : String, @description : String? = nil)
        @nodes = [] of WorkflowNode
        @committed = false
        @default_model = nil
        @default_skills = [] of String
        @default_tools = [] of String
        @default_logger = nil.as(AnyHash?)
        @node_loggers = {} of String => AnyHash
        @default_workspace = nil.as(AnyHash?)
        @node_workspaces = {} of String => AnyHash
        @pending_node_workspace = nil.as(AnyHash?)
        @resource_scope_stack = [] of ResourceScope
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

      # Unified resource defaults for model, skills, and tools
      # Supports: model: "...", skill: ["..."], tool: ["..."]
      def resources(
        model : String? = nil,
        skill : (String | Array(String))? = nil,
        tool : (String | Array(String))? = nil
      ) : self
        ensure_not_committed!

        if model
          normalized = model.strip
          raise "resources requires non-empty model string" if normalized.empty?
          @default_model = normalized
        end

        if skill
          skills = normalize_to_array(skill)
          skills.each do |s|
            @default_skills << s unless @default_skills.includes?(s)
          end
        end

        if tool
          tools = normalize_to_array(tool)
          tools.each do |t|
            @default_tools << t unless @default_tools.includes?(t)
          end
        end

        self
      end

      # Block-scoped resource defaults
      # Applies resources only within the block, then restores previous state
      def resources(
        model : String? = nil,
        skill : (String | Array(String))? = nil,
        tool : (String | Array(String))? = nil,
        &block
      ) : self
        ensure_not_committed!

        # Save current state
        previous_model = @default_model
        previous_skills = @default_skills.dup
        previous_tools = @default_tools.dup

        # Push new scope
        scope = ResourceScope.new(
          model: model,
          skills: skill ? normalize_to_array(skill) : nil,
          tools: tool ? normalize_to_array(tool) : nil
        )
        @resource_scope_stack << scope

        # Apply scoped resources
        @default_model = model if model
        if skill
          normalize_to_array(skill).each do |s|
            @default_skills << s unless @default_skills.includes?(s)
          end
        end
        if tool
          normalize_to_array(tool).each do |t|
            @default_tools << t unless @default_tools.includes?(t)
          end
        end

        # Execute block
        block.call

        # Restore previous state
        @resource_scope_stack.pop
        @default_model = previous_model
        @default_skills = previous_skills
        @default_tools = previous_tools

        self
      end

      private def normalize_to_array(value : String | Array(String)) : Array(String)
        case value
        when String
          [value]
        when Array(String)
          value
        else
          [] of String
        end
      end
    end
  end
end
