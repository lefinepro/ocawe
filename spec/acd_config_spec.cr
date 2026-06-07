require "./spec_helper"

describe Ocawe::Config::Settings do
  it "loads workflow defaults from typed crystal config" do
    config = Ocawe::Config::Settings.default
    config.workflows.preferred_workflows_root.should eq("./src/workflows")
  end

  it "loads federation auto_subscribe from rcl config" do
    path = File.tempname("ocawe-config", ".rcl")
    File.write(path, <<-RCL)
      federation do
        auto_subscribe = ["@oq.col.pub", "@planner@oq.col.pub"]
      end
    RCL

    config = OcaweCore::Utils::ConfigParser.load_settings(Ocawe::Config::Settings.default, rcl_path: path)
    config.federation.auto_subscribe.should eq(["@oq.col.pub", "@planner@oq.col.pub"])
  ensure
    File.delete(path) if path && File.exists?(path)
  end
end
