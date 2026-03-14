require "./spec_helper"

describe "workspace bootstrap in settings" do
  it "runs workspace bootstrap during configured function registration" do
    called = false
    settings = Cogni::Config::Settings.new(
      workflows: Cogni::Config::WorkflowSettings.new(
        preferred_workflows_root: "./shards/examples",
      ),
      workspace_bootstrap: -> : Nil do
        called = true
        Cogni::RegistryApi.workspace_resolver do |workspace|
          resolved = JSON.parse(workspace.to_json).as_h
          resolved["from_bootstrap"] = json_bool(true)
          resolved
        end
      end,
    )

    app = ACD::Kemal::App.new(0, settings: settings)
    app.test_register_configured_functions!

    workflow = Cogni::Workflow.create_workflow("workspace-bootstrap")
    workflow
      .workspace({"provider" => json_str("docker")})
      .agent_codex("noop")
      .commit

    workspace = workflow.nodes.first.metadata["workspace"].as_h
    called.should eq(true)
    workspace["from_bootstrap"].raw.should eq(true)
  end
end
