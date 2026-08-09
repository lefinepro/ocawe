require "./spec_helper"

describe "Commands API example" do
  it "loads the example without an explicit plugin require" do
    root = File.expand_path("../caws/14-commands-api", __DIR__)
    bundle = ACD::Discovery::CawfileLoader.load(root, "14-commands-api").not_nil!
    loader = bundle.crystal_loader.not_nil!

    loader.requires.should be_empty
    loader.registry_files.map { |path| Path[path].relative_to(Path[root]).to_s }.should eq([
      "plugins/commands/set_value.cr",
    ])
    bundle.dsl_source.not_nil!.join.should contain("input.command.\"generate_code\"")
    File.read(File.join(root, "README.org")).should contain("COGNICORE_MOCK_LLM")
  end
end
