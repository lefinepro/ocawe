require "option_parser"
require "../shards/agent-functions/src/cogni-agent-functions"
require "./framework/utils/config_parser"
require "./framework/cognicore/version"
require "./framework/workflows/dsl/types"
require "./framework/workflows/dsl/crystal_dsl"
require "./framework/workflows/declarative/run"
require "./framework/workflows/declarative/api"
require "./framework/registry/api"
require "./framework/config/settings"
require "./framework/trigger/public_api"
require "./framework/http/app"

module CogniCore
  DEFAULT_PORT = 4111

  def self.run
    CogniCore::Utils::ConfigParser.load_dotenv
    settings = Cogni::Config::Settings.default

    port = DEFAULT_PORT
    workflows_root = nil.as(String?)
    config_rcl = nil.as(String?)

    OptionParser.parse do |parser|
      parser.banner = "Usage: cognicore [arguments]"
      parser.on("-p PORT", "--port=PORT", "HTTP port") { |value| port = value.to_i }
      parser.on("--workflows-root=PATH", "Preferred workflows root path") { |value| workflows_root = value }
      parser.on("--config-rcl=PATH", "RCL config file path (alternative to Crystal-only defaults)") { |value| config_rcl = value }
      parser.on("-v", "--version", "Print version") do
        puts VERSION
        exit(0)
      end
      parser.on("-h", "--help", "Show help") do
        puts parser
        exit(0)
      end
    end

    settings = CogniCore::Utils::ConfigParser.load_settings(settings, rcl_path: config_rcl)

    # Use default config values if not overridden by command line
    workflows_root ||= settings.workflows.preferred_workflows_root
    

    ACD::Kemal::App.new(
      port,
      workflows_root: workflows_root,
      settings: settings,
    ).start
  end
end

{% if flag?(:cogni_runtime_main) %}
  CogniCore.run
{% end %}
