require "./default_function_handlers"

module CogniCore
  module Config
    # Configuration settings defined directly in Crystal code
    class AppConfig
      # Workflow settings
      WORKFLOW_PREFERRED_ROOT = "./src/workflows"
      WORKFLOW_FALLBACK_ROOT = "./src/workflows"

      # Get all settings as a unified configuration object
      def self.settings : Settings
        functions = {
          "agent_opencode" => DefaultFunctionHandlers.agent_opencode,
          "agent_codex" => DefaultFunctionHandlers.agent_codex,
          "agent_cliproxy" => DefaultFunctionHandlers.agent_cliproxy,
        } of String => CogniCore::Workflow::FunctionHandler

        Settings.new(
          workflows: WorkflowSettings.new(
            preferred_workflows_root: WORKFLOW_PREFERRED_ROOT,
            fallback_workflows_root: WORKFLOW_FALLBACK_ROOT
          ),
          functions: functions
        )
      end

      struct WorkflowSettings
        getter preferred_workflows_root : String
        getter fallback_workflows_root : String

        def initialize(@preferred_workflows_root : String, @fallback_workflows_root : String)
        end
      end

      struct Settings
        getter workflows : WorkflowSettings
        getter functions : Hash(String, CogniCore::Workflow::FunctionHandler)

        def initialize(
          @workflows : WorkflowSettings,
          @functions : Hash(String, CogniCore::Workflow::FunctionHandler)
        )
        end
      end
    end
  end
end
