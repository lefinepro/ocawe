module CogniCore
  module Config
    struct WorkflowSettings
      getter preferred_workflows_root : String
      getter fallback_workflows_root : String

      def initialize(
        @preferred_workflows_root : String = "./src/workflows",
        @fallback_workflows_root : String = "./src/workflows"
      )
      end
    end

    struct CompilerSettings
      getter output : String

      def initialize(@output : String = "generated/registry.cr")
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

      def initialize(@runtimes : Array(RuntimeSpec) = [] of RuntimeSpec, @download_path : String = "runtime_cache")
      end
    end

    struct Settings
      getter workflows : WorkflowSettings
      getter compiler : CompilerSettings
      getter runtime : RuntimeSettings

      def initialize(
        @workflows : WorkflowSettings = WorkflowSettings.new,
        @compiler : CompilerSettings = CompilerSettings.new,
        @runtime : RuntimeSettings = RuntimeSettings.new
      )
      end
    end

    module ACDConfig
      SETTINGS = Settings.new

      def self.settings : Settings
        SETTINGS
      end
    end
  end
end
