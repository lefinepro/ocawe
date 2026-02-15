require "./spec_helper"

describe CogniCore::Config::AppConfig do
  it "loads workflow defaults from crystal config" do
    config = CogniCore::Config::AppConfig.settings
    config.workflows.preferred_workflows_root.should eq("./src/workflows")
    config.workflows.fallback_workflows_root.should eq("./src/workflows")
  end
end
