require "option_parser"
require "./framework/utils/config_parser"
require "./framework/cognicore/version"
require "./framework/cognicore/config/app_config"
require "./framework/cognicore/schema/types"
require "./framework/cognicore/schema/crystal_dsl"
require "./framework/cognicore/workflow/run"
require "./framework/cogni/public_api"
require "./framework/http/app"

module CogniCore
  DEFAULT_PORT = 4111

  def self.run
    CogniCore::Utils::ConfigParser.load_dotenv

    port = DEFAULT_PORT
    workflows_root = nil.as(String?)
    fallback_workflows_root = nil.as(String?)

    OptionParser.parse do |parser|
      parser.banner = "Usage: cognicore [arguments]"
      parser.on("-p PORT", "--port=PORT", "HTTP port") { |value| port = value.to_i }
      parser.on("--workflows-root=PATH", "Preferred workflows root path") { |value| workflows_root = value }
      parser.on("--fallback-workflows-root=PATH", "Fallback workflows root path") { |value| fallback_workflows_root = value }
      parser.on("-v", "--version", "Print version") do
        puts VERSION
        exit(0)
      end
      parser.on("-h", "--help", "Show help") do
        puts parser
        exit(0)
      end
    end

    # Use default config values if not overridden by command line
    workflows_root ||= CogniCore::Config::AppConfig::WORKFLOW_PREFERRED_ROOT
    fallback_workflows_root ||= CogniCore::Config::AppConfig::WORKFLOW_FALLBACK_ROOT

    ACD::HTTP::App.new(port, workflows_root: workflows_root, fallback_workflows_root: fallback_workflows_root).start
  end
end
