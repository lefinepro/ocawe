require "./spec_helper"
require "../src/framework/cognicore/config/acd_toml"

describe CogniCore::Config::ACDToml do
  it "loads workflow roots from acd config" do
    config = CogniCore::Config::ACDToml.load(".meta/acd.toml")
    config.preferred_workflows_root.should eq("./src/workflows")
    config.fallback_workflows_root.should eq("./src/workflows")
  end
end
