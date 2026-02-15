module CogniCore
  module Config
    # Example: Crystal-native framework config
    class AppConfig
      WORKFLOW_PREFERRED_ROOT = "./shards/examples/full-capabilities"
      WORKFLOW_FALLBACK_ROOT = "./shards/examples"

      def self.settings : Settings
        Settings.new(
          workflows: WorkflowSettings.new(
            preferred_workflows_root: WORKFLOW_PREFERRED_ROOT,
            fallback_workflows_root: WORKFLOW_FALLBACK_ROOT
          )
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

        def initialize(@workflows : WorkflowSettings)
        end
      end
    end
  end
end
