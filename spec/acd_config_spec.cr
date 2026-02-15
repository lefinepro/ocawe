require "./spec_helper"

describe CogniCore::Config::AppConfig do
  it "loads workflow/compiler/runtime defaults from crystal config" do
    config = CogniCore::Config::AppConfig.settings
    config.workflows.preferred_workflows_root.should eq("./src/workflows")
    config.workflows.fallback_workflows_root.should eq("./src/workflows")
    config.compiler.output.should eq("generated/registry.cr")
    config.runtime.download_path.should eq("runtime_cache")
    config.runtime.runtimes.should be_empty
  end
end
