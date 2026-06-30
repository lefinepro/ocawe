require "option_parser"
require "./framework/utils/config_parser"
require "./framework/api/public_types"
require "./framework/version"
require "./framework/workflows/dsl/types"
require "./framework/workflows/dsl/crystal_dsl"
require "./framework/workflows/declarative/run"
require "./framework/workflows/declarative/api"
require "./framework/registry/api"
require "./framework/config/settings"
require "./framework/trigger/public_api"
require "./framework/http/app"
require "./framework/acp"

module OcaweCore
  DEFAULT_PORT = 4111

  def self.run
    OcaweCore::Utils::ConfigParser.load_dotenv
    settings = Ocawe::Config::Settings.default
    start_settings = OcaweCore::Utils::ConfigParser.load_start_settings(Ocawe::Config::StartSettings.new)

    port = start_settings.port
    workflows_root = start_settings.workflows_root.as(String?)
    log_level = start_settings.log_level
    config_rcl = nil.as(String?)

    OptionParser.parse do |parser|
      parser.banner = "Usage: ocawecore [arguments]"
      parser.on("-p PORT", "--port=PORT", "HTTP port") { |value| port = value.to_i }
      parser.on("--workflows-root=PATH", "Preferred workflows root path") { |value| workflows_root = value }
      parser.on("--log-level=LEVEL", "Log level: debug, warning, critical") { |value| log_level = Ocawe::Config::LogLevel.parse(value) }
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

    settings = OcaweCore::Utils::ConfigParser.load_settings(settings, rcl_path: config_rcl)

    # Use default config values if not overridden by command line
    workflows_root ||= settings.workflows.preferred_workflows_root

    ENV["OCAWE_PORT"] = port.to_s

    ACD::Kemal::App.new(
      port,
      workflows_root: workflows_root,
      settings: settings,
    ).start
  end
end

{% if flag?(:ocawe_runtime_main) %}
  OcaweCore.run
{% end %}
