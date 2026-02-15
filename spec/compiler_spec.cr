require "./spec_helper"
require "../src/framework/cognicore/compiler/compiler"

describe CogniCore::Compiler::Compiler::Config do
  it "loads workflow defaults from crystal config" do
    config = CogniCore::Compiler::Compiler::Config.load
    config.preferred_workflows_root.should eq("./src/workflows")
    config.fallback_workflows_root.should eq("./src/workflows")
    config.output.should eq("generated/registry.cr")
  end
end
