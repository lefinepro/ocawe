module CogniCore
  module Config
    # Configuration settings defined directly in Crystal code
    class AppConfig
      # Workflow settings
      WORKFLOW_PREFERRED_ROOT = "./src/workflows"
      WORKFLOW_FALLBACK_ROOT = "./src/workflows"

      # Compiler settings  
      COMPILER_OUTPUT = "generated/registry.cr"

      # Runtime settings
      RUNTIME_DOWNLOAD_PATH = "runtime_cache"
      
      # Default runtime specifications
      DEFAULT_RUNTIMES = [] of RuntimeSpec

      # Get all settings as a unified configuration object
      def self.settings : Settings
        Settings.new(
          workflows: WorkflowSettings.new(
            preferred_workflows_root: WORKFLOW_PREFERRED_ROOT,
            fallback_workflows_root: WORKFLOW_FALLBACK_ROOT
          ),
          compiler: CompilerSettings.new(output: COMPILER_OUTPUT),
          runtime: RuntimeSettings.new(runtimes: DEFAULT_RUNTIMES, download_path: RUNTIME_DOWNLOAD_PATH)
        )
      end

      struct WorkflowSettings
        getter preferred_workflows_root : String
        getter fallback_workflows_root : String

        def initialize(@preferred_workflows_root : String, @fallback_workflows_root : String)
        end
      end

      struct CompilerSettings
        getter output : String

        def initialize(@output : String)
        end
      end

      struct RuntimeSpec
        getter language : String
        getter runtime_url : String
        getter version : String
        getter entrypoint : String

        def initialize(@language : String, @runtime_url : String, @version : String, @entrypoint : String)
        end
      end

      struct RuntimeSettings
        getter runtimes : Array(RuntimeSpec)
        getter download_path : String

        def initialize(@runtimes : Array(RuntimeSpec), @download_path : String)
        end
      end

      struct Settings
        getter workflows : WorkflowSettings
        getter compiler : CompilerSettings
        getter runtime : RuntimeSettings

        def initialize(@workflows : WorkflowSettings, @compiler : CompilerSettings, @runtime : RuntimeSettings)
        end
      end
    end
  end
end