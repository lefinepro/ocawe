require "./spec_helper"
require "../src/cli/app"

describe OcaweCore::CLI::Main do
  it "prints version on --version" do
    output = `#{File.expand_path("bin/ocawe")} --version`
    output.includes?("0.1.0").should eq(true)
  end

  it "prints help on --help" do
    output = `#{File.expand_path("bin/ocawe")} --help`
    output.includes?("Usage: ocawe").should eq(true)
    output.includes?("build").should eq(true)
    output.includes?("up").should eq(true)
  end

  it "prints help on unknown command" do
    output = `#{File.expand_path("bin/ocawe")} unknown 2>&1`
    output.includes?("Unknown command").should eq(true)
  end

  it "mentions container build in help" do
    output = `#{File.expand_path("bin/ocawe")} --help`
    output.includes?("container").should eq(true)
    output.includes?("@[Container]").should eq(true)
  end
end
