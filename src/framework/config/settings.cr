require "./default_function_handlers"

module Cogni
  module Config
    struct WorkflowSettings
      getter preferred_workflows_root : String
      getter fallback_workflows_root : String

      def initialize(@preferred_workflows_root : String, @fallback_workflows_root : String)
      end
    end

    struct NodeKindSettings
      getter enabled : Array(String)

      def initialize(@enabled : Array(String) = [] of String)
      end
    end

    struct Settings
      getter workflows : WorkflowSettings
      getter node_kinds : NodeKindSettings
      getter functions : Hash(String, Cogni::Workflows::Declarative::FunctionHandler)

      def initialize(
        @workflows : WorkflowSettings,
        @node_kinds : NodeKindSettings = NodeKindSettings.new,
        @functions : Hash(String, Cogni::Workflows::Declarative::FunctionHandler) = {} of String => Cogni::Workflows::Declarative::FunctionHandler
      )
      end

      def self.default : Settings
        functions = {
          "agent_opencode" => DefaultFunctionHandlers.agent_opencode,
          "agent_codex" => DefaultFunctionHandlers.agent_codex,
          "agent_cliproxy" => DefaultFunctionHandlers.agent_cliproxy,
        } of String => Cogni::Workflows::Declarative::FunctionHandler

        new(
          workflows: WorkflowSettings.new(
            preferred_workflows_root: "./src/workflows",
            fallback_workflows_root: "./src/workflows"
          ),
          node_kinds: NodeKindSettings.new,
          functions: functions
        )
      end
    end
  end
end
