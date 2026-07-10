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
require "./framework/discovery/cawfile_loader"
require "./framework/integration/pipeline_helpers"
require "./framework/secrets/store"
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
    log_level = start_settings.log_level
    config_rcl = nil.as(String?)

    OptionParser.parse do |parser|
      parser.banner = "Usage: ocawecore [arguments]"
      parser.on("-p PORT", "--port=PORT", "HTTP port") { |value| port = value.to_i }
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

    workflows_root = Dir.current
    if bundle = ACD::Discovery::CawfileLoader.load_root(workflows_root)
      settings = OcaweCore::Utils::ConfigParser.apply_cawfile_settings(settings, bundle)
    end
    auto_start_environment(workflows_root)

    ENV["OCAWE_PORT"] = port.to_s

    ACD::Kemal::App.new(
      port,
      settings: settings,
    ).start
  end

  def self.auto_start_environment(workflows_root : String) : Nil
    script = File.join(workflows_root, "start-dev-environment.sh")
    return unless File.exists?(script)

    status = Process.run(
      "bash",
      args: ["-lc", "./start-dev-environment.sh"],
      chdir: workflows_root,
      input: Process::Redirect::Close,
      output: Process::Redirect::Inherit,
      error: Process::Redirect::Inherit
    )
    unless status.success?
      STDERR.puts "[ocawecore] start-dev-environment.sh failed"
      exit(1)
    end
  end
end

{% if flag?(:ocawe_runtime_main) %}
  OcaweCore.run
{% end %}
