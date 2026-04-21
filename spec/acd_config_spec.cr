require "./spec_helper"

describe Cogni::Config::Settings do
  it "loads workflow defaults from typed crystal config" do
    config = Cogni::Config::Settings.default
    config.workflows.preferred_workflows_root.should eq("./src/workflows")
  end

  it "loads federation auto_subscribe from rcl config" do
    path = File.tempname("cogni-config", ".rcl")
    File.write(path, <<-RCL)
      federation do
        auto_subscribe = ["@oq.col.pub", "@planner@oq.col.pub"]
      end
    RCL

    config = CogniCore::Utils::ConfigParser.load_settings(Cogni::Config::Settings.default, rcl_path: path)
    config.federation.auto_subscribe.should eq(["@oq.col.pub", "@planner@oq.col.pub"])
  ensure
    File.delete(path) if path && File.exists?(path)
  end

  it "loads ml registry and backend priority from rcl config" do
    path = File.tempname("cogni-ml-config", ".rcl")
    File.write(path, <<-RCL)
      ml do
        registry_adapter = "file"
        file_root = "./tmp/ml"
        default_runtime_adapter = "cogni_ml"
        backend_priority = ["cuda", "amd", "metal"]
      end
    RCL

    config = CogniCore::Utils::ConfigParser.load_settings(Cogni::Config::Settings.default, rcl_path: path)
    config.ml.registry_adapter.should eq("file")
    config.ml.file_root.should eq("./tmp/ml")
    config.ml.backend_priority.should eq(["cuda", "amd", "metal"])
  ensure
    File.delete(path) if path && File.exists?(path)
  end
end
