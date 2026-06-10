require "./spec_helper"
require "file_utils"
require "../src/framework/discovery/cawfile_loader"

describe ACD::Discovery::WorkflowLocator do
  describe "Cawfile primary support" do
    it "resolves a bundle from Cawfile when present" do
      root = File.tempname("wf_loc")
      Dir.mkdir_p(root)
      begin
        workflow_dir = File.join(root, "my-caw")
        Dir.mkdir(workflow_dir)
        File.write(File.join(workflow_dir, "Cawfile"), "workflow \"my-caw\" do\n  agent \"analyzer\"\nend\n")
        locator = ACD::Discovery::WorkflowLocator.new(root)
        bundle = locator.resolve("my-caw")
        bundle.id.should eq("my-caw")
        bundle.cawfile.should_not be_nil
        bundle.cawfile.not_nil!.id.should eq("my-caw")
        bundle.workflow_file.should eq(File.join(workflow_dir, "Cawfile"))
      ensure
        FileUtils.rm_rf(root)
      end
    end

    it "falls back to .acd.cr when no Cawfile exists" do
      root = File.tempname("wf_loc")
      Dir.mkdir_p(root)
      begin
        workflow_dir = File.join(root, "legacy")
        Dir.mkdir(workflow_dir)
        File.write(File.join(workflow_dir, "legacy.acd.cr"), "workflow \"legacy\" do\n  agent \"legacy-agent\"\nend\n")
        locator = ACD::Discovery::WorkflowLocator.new(root)
        bundle = locator.resolve("legacy")
        bundle.cawfile.should be_nil
        bundle.workflow_file.should eq(File.join(workflow_dir, "legacy.acd.cr"))
      ensure
        FileUtils.rm_rf(root)
      end
    end

    it "raises when neither Cawfile nor .acd.cr exists" do
      root = File.tempname("wf_loc")
      Dir.mkdir_p(root)
      begin
        workflow_dir = File.join(root, "empty")
        Dir.mkdir(workflow_dir)
        locator = ACD::Discovery::WorkflowLocator.new(root)
        expect_raises(Exception) { locator.resolve("empty") }
      ensure
        FileUtils.rm_rf(root)
      end
    end
  end
end
