require "./spec_helper"
require "../src/cli/remote_runner"

describe OcaweCore::CLI::RemoteRunner do
  it "validates a workflow path and prints connection details in dry-run mode" do
    runner = OcaweCore::CLI::RemoteRunner.new(Dir.current)
    options = OcaweCore::CLI::RemoteRunner::Options.new(profile: "@handle@lefine.pro", dry_run: true)

    runner.up("caws/01-simple", options).should be_true
  end

  it "uses the device actor by default" do
    OcaweCore::CLI::RemoteRunner::Options.new(profile: "@handle@lefine.pro").actor.should eq("https://lefine.pro/actors/ocawe-device")
  end

  it "does not persist a task during a dry run" do
    runner = OcaweCore::CLI::RemoteRunner.new(Dir.current)
    options = OcaweCore::CLI::RemoteRunner::Options.new(profile: "@handle@lefine.pro", dry_run: true)
    auth_path = File.join(Dir.current, "caws", "01-simple", ".ocawe", "remote-task.json")
    was_present = File.exists?(auth_path)
    runner.up("caws/01-simple", options).should be_true
    File.exists?(auth_path).should eq(was_present)
  end
end
