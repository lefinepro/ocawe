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

          key, value = parse_assignment(line)
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

      private def self.parse_assignment(line : String) : Tuple(String?, String)
        parts = line.split("=", 2)
        return {nil, ""} if parts.size < 2
        key = parts[0].strip
        raw = parts[1].strip
        value = raw
        if raw.starts_with?('"') && raw.ends_with?('"') && raw.size >= 2
          value = raw[1...-1]
        end
        {key, value}
      end
    end
  end
end
