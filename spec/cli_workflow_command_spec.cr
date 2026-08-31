require "./spec_helper"
require "../src/cli/app"

module CliWorkflowCommandSpec
  def self.cli_output(args : String) : String
    `crystal run #{File.expand_path("src/cli/main.cr")} -- #{args}`
  end
end

describe OcaweCore::CLI::Main do
  it "prints version on --version" do
    output = CliWorkflowCommandSpec.cli_output("--version")
    output.strip.should eq(OcaweCore::VERSION)
  end

  it "prints help on --help" do
    output = CliWorkflowCommandSpec.cli_output("--help")
    output.includes?("Usage: ocawe").should eq(true)
    output.includes?("build").should eq(true)
    output.includes?("dev").should eq(true)
    output.includes?("up").should eq(true)
    output.includes?("start").should eq(true)
    output.includes?("stop").should eq(true)
    output.includes?("pull REF").should eq(true)
  end

  it "prints help on unknown command" do
    output = CliWorkflowCommandSpec.cli_output("unknown 2>&1")
    output.includes?("Unknown command").should eq(true)
  end

  it "does not mention container configuration in help" do
    output = CliWorkflowCommandSpec.cli_output("--help")
    output.includes?("container").should eq(false)
    output.includes?("container do").should eq(false)
  end

  it "supports remote up with a path selector in dry-run mode" do
    output = CliWorkflowCommandSpec.cli_output("up --remote \\@handle@lefine.pro caws/01-simple --dry-run")
    output.includes?("ActivityPub dry-run").should eq(true)
    output.includes?("project.tar.zst").should eq(true)
    output.includes?("Profile: https://lefine.pro/actors/handle").should eq(true)
    output.includes?("Task: https://lefine.pro/actors/ocawe-device/activities/ocawe-task-").should eq(true)
    output.includes?("ssh").should eq(false)
  end
end
