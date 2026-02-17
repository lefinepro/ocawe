require "./spec_helper"

describe Cogni::Config::Settings do
  it "loads workflow defaults from typed crystal config" do
    config = Cogni::Config::Settings.default
    config.workflows.preferred_workflows_root.should eq("./src/workflows")
    config.workflows.fallback_workflows_root.should eq("./src/workflows")
  end
end
