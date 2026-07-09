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
    output.includes?("0.1.0").should eq(true)
  end

  it "prints help on --help" do
    output = CliWorkflowCommandSpec.cli_output("--help")
    output.includes?("Usage: ocawe").should eq(true)
    output.includes?("build").should eq(true)
    output.includes?("up").should eq(true)
    output.includes?("pull REF").should eq(true)
  end

  it "prints help on unknown command" do
    output = CliWorkflowCommandSpec.cli_output("unknown 2>&1")
    output.includes?("Unknown command").should eq(true)
  end

  it "mentions container build in help" do
    output = CliWorkflowCommandSpec.cli_output("--help")
    output.includes?("container").should eq(true)
    output.includes?("container do").should eq(true)
  end
end
