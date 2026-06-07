require "ocawe"
require "option_parser"
require "./app_config"

module OcaweDockerGit
  VERSION = "0.1.0"

  extend self

  def run
    port = 4222
    OptionParser.parse do |parser|
      parser.banner = "Usage: docker_git [arguments]"
      parser.on("-p PORT", "--port=PORT", "HTTP port") { |value| port = value.to_i }
      parser.on("-h", "--help", "Show help") do
        puts parser
        exit(0)
      end
    end

    settings = AppConfig.settings
    root = AppConfig.workflows_root
    ACD::HTTP::App.new(
      port,
      workflows_root: root,
      preferred_workflows_root: root,
      settings: settings,
    ).start
  end

  def bootstrap_workspace_extensions! : Nil
    Ocawe::RegistryApi.workspace_schema("workspace_provider_required") do |workspace|
      unless provider = workspace["provider"]?.try(&.as_s?)
        raise "workspace.provider is required"
      end
      raise "workspace.provider must be non-empty" if provider.empty?
    end

    Ocawe::RegistryApi.workspace_resolver do |workspace|
      resolved = JSON.parse(workspace.to_json).as_h
      resolved["resolved_by"] = JSON.parse("ocawe-docker-git".to_json)
      resolved["runtime"] = JSON.parse((resolved["runtime"]?.try(&.as_s?) || "docker").to_json)
      resolved
    end

    Ocawe::RegistryApi.workspace_hook("before_node") do |ctx, workspace|
      puts "[docker-git] before #{ctx.node_id} workspace=#{workspace.to_json}"
    end
    Ocawe::RegistryApi.workspace_hook("after_node") do |ctx, workspace|
      puts "[docker-git] after #{ctx.node_id} workspace=#{workspace.to_json}"
    end
    Ocawe::RegistryApi.workspace_hook("on_error") do |ctx, workspace|
      STDERR.puts "[docker-git] error #{ctx.node_id} workspace=#{workspace.to_json}"
    end
  end
end

OcaweDockerGit.run
