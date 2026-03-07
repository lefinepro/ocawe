require "./spec_helper"
require "file_utils"

describe "workspace annotation and registry integration" do
  it "resolves workflow and node workspace config through registry handlers" do
    Cogni::RegistryApi.reset_all!

    Cogni::RegistryApi.workspace_schema("provider_required") do |config|
      raise "workspace.provider is required" unless config["provider"]?.try(&.as_s?)
    end
    Cogni::RegistryApi.workspace_resolver do |config|
      resolved = JSON.parse(config.to_json).as_h
      resolved["resolved"] = json_bool(true)
      resolved
    end

    workflow = Cogni::Workflow.create_workflow("workspace-resolution")
    workflow
      .workspace({
        "provider" => json_str("docker"),
        "repo" => json_str("org/repo"),
      })
      .agent_codex("noop")
      .workspace_next({
        "branch" => json_str("main"),
      })
      .agent_codex("noop2")
      .commit

    first_workspace = workflow.nodes[0].metadata["workspace"].as_h
    second_workspace = workflow.nodes[1].metadata["workspace"].as_h

    first_workspace["provider"].as_s.should eq("docker")
    first_workspace["repo"].as_s.should eq("org/repo")
    first_workspace["resolved"].raw.should eq(true)
    second_workspace["provider"].as_s.should eq("docker")
    second_workspace["branch"].as_s.should eq("main")
    second_workspace["resolved"].raw.should eq(true)
  end

  it "injects workspace into run envelope and emits workspace hooks" do
    Cogni::RegistryApi.reset_all!
    events = [] of String
    fn_name = "capture_workspace_#{Random.rand(1_000_000)}"

    Cogni::RegistryApi.workspace_hook("before_node") do |ctx, workspace|
      events << "before:#{ctx.node_id}:#{workspace["provider"]?.try(&.as_s?) || "none"}"
    end
    Cogni::RegistryApi.workspace_hook("after_node") do |ctx, workspace|
      events << "after:#{ctx.node_id}:#{workspace["provider"]?.try(&.as_s?) || "none"}"
    end

    Cogni::RegistryApi.register_function(fn_name) do |ctx|
      workspace = ctx.input_data["workspace"]?.try(&.as_h?) || ({} of String => JSON::Any)
      {
        "workspace_provider" => workspace["provider"]? || json_str("missing"),
        "workspace_branch" => workspace["branch"]? || json_str("none"),
      }
    end
    Cogni::RegistryApi.node_kind(fn_name) do |ctx, _parameters|
      Cogni::RegistryApi.call_function(fn_name, ctx)
    end

    workflow = Cogni::Workflow.create_workflow("workspace-run")
    workflow
      .workspace({
        "provider" => json_str("docker"),
        "branch" => json_str("main"),
      })
      .step(Cogni::NodeKind.new(fn_name), id: fn_name)
      .commit

    engine = Cogni::Workflow::Engine.new
    engine.register(workflow)
    result = engine.create_run("workspace-run").start

    result.status.should eq("success")
    result.state.not_nil!["workspace_provider"].as_s.should eq("docker")
    result.state.not_nil!["workspace_branch"].as_s.should eq("main")
    events.should eq(["before:#{fn_name}:docker", "after:#{fn_name}:docker"])
  end

  it "parses @[Workspace(...)] and rejects deprecated docker use syntax" do
    Cogni::RegistryApi.reset_all!
    tmp_dir = "/tmp/cogni_workspace_annotation_#{Random.rand(1_000_000)}"
    Dir.mkdir_p(tmp_dir)

    begin
      workflow_file = File.join(tmp_dir, "workspace.acd.cr")
      File.write(workflow_file, <<-WORKFLOW)
workflow "workspace-annotation" do
  @[Workspace(provider: "docker", repo: "org/repo", scope: "workflow")]
  exec "noop", runtime: {shell: "bash"}

  @[Workspace(branch: "main")]
  exec "noop2", runtime: {shell: "bash"}
end
WORKFLOW

      bundle = ACD::Discovery::WorkflowBundle.new(
        id: "workspace-annotation",
        root_path: tmp_dir,
        workflow_file: workflow_file,
        agents_dir: File.join(tmp_dir, "agents"),
        skills_dir: File.join(tmp_dir, "skills"),
        source_root_type: "preferred",
      )
      app = ACD::Kemal::App.new(0)
      definition = app.test_load_workflow_definition(bundle, [] of ACD::Agents::LoadedAgent)

      definition.nodes.size.should eq(2)
      definition.nodes[0].metadata["workspace"].as_h["repo"].as_s.should eq("org/repo")
      definition.nodes[1].metadata["workspace"].as_h["branch"].as_s.should eq("main")

      deprecated_file = File.join(tmp_dir, "deprecated.acd.cr")
      File.write(deprecated_file, <<-WORKFLOW)
workflow "workspace-deprecated" do
  docker use "workspace-a"
  exec "noop", runtime: {shell: "bash"}
end
WORKFLOW

      deprecated_bundle = ACD::Discovery::WorkflowBundle.new(
        id: "workspace-deprecated",
        root_path: tmp_dir,
        workflow_file: deprecated_file,
        agents_dir: File.join(tmp_dir, "agents"),
        skills_dir: File.join(tmp_dir, "skills"),
        source_root_type: "preferred",
      )

      expect_raises(Exception, /docker use.*deprecated/) do
        app.test_load_workflow_definition(deprecated_bundle, [] of ACD::Agents::LoadedAgent)
      end
    ensure
      FileUtils.rm_rf(tmp_dir)
    end
  end
end
