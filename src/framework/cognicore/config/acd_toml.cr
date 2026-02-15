require "../../../framework/utils/config_parser"

module CogniCore
  module Config
    struct ACDSettings
      getter preferred_workflows_root : String
      getter fallback_workflows_root : String

      def initialize(
        @preferred_workflows_root : String = "./src/workflows",
        @fallback_workflows_root : String = "./src/workflows"
      )
      end
    end

    class ACDToml
      DEFAULT_PATH = ".meta/acd.toml"

      def self.load(path : String = DEFAULT_PATH) : ACDSettings
        return ACDSettings.new unless File.exists?(path)

        preferred = "./src/workflows"
        fallback = "./src/workflows"
        section = ""

        File.each_line(path) do |raw|
          line = raw.strip
          next if line.empty? || line.starts_with?("#")

          if line == "[workflows]"
            section = "workflows"
            next
          end

          key, value = CogniCore::Utils::ConfigParser.parse_assignment(line)
          next unless key
          next unless section == "workflows"

          preferred = value if key == "preferred_root"
          fallback = value if key == "fallback_root"
        end

        ACDSettings.new(
          preferred_workflows_root: preferred,
          fallback_workflows_root: fallback,
        )
      end
    end
  end
end
