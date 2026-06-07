require "./spec_helper"
require "tempfile"
require "../src/framework/discovery/cawfile_loader"

describe ACD::Discovery::WorkflowLocator do
  describe "Cawfile primary support" do
    it "resolves a bundle from Cawfile when present" do
      Dir.mktmpdir do |root|
        workflow_dir = File.join(root, "my-caw")
        Dir.mkdir(workflow_dir)
        File.write(File.join(workflow_dir, "Cawfile"), <<-YAML)
          id: my-caw
          description: Cawfile driven workflow
          workflow:
            steps:
              - type: agent
                id: test-agent
        YAML
        locator = ACD::Discovery::WorkflowLocator.new(root)
        bundle = locator.resolve("my-caw")
        bundle.id.should eq("my-caw")
        bundle.cawfile.should_not be_nil
        bundle.cawfile.not_nil!.description.should eq("Cawfile driven workflow")
        bundle.workflow_file.should eq(File.join(workflow_dir, "Cawfile"))
      end
    end

    it "resolves a bundle from Cawfile with explicit workflow_file" do
      Dir.mktmpdir do |root|
        workflow_dir = File.join(root, "hybrid")
        Dir.mkdir(workflow_dir)
        File.write(File.join(workflow_dir, "Cawfile"), <<-YAML)
          id: hybrid
          workflow_file: hybrid.acd.cr
        YAML
        File.write(File.join(workflow_dir, "hybrid.acd.cr"), <<-CRYSTAL)
          workflow "hybrid" do
            agent "fallback-agent"
          end
        CRYSTAL
        locator = ACD::Discovery::WorkflowLocator.new(root)
        bundle = locator.resolve("hybrid")
        bundle.workflow_file.should eq(File.join(workflow_dir, "hybrid.acd.cr"))
        bundle.cawfile.should_not be_nil
      end
    end

    it "falls back to .acd.cr when no Cawfile exists" do
      Dir.mktmpdir do |root|
        workflow_dir = File.join(root, "legacy")
        Dir.mkdir(workflow_dir)
        File.write(File.join(workflow_dir, "legacy.acd.cr"), <<-CRYSTAL)
          workflow "legacy" do
            agent "legacy-agent"
          end
        CRYSTAL
        locator = ACD::Discovery::WorkflowLocator.new(root)
        bundle = locator.resolve("legacy")
        bundle.cawfile.should be_nil
        bundle.workflow_file.should eq(File.join(workflow_dir, "legacy.acd.cr"))
      end
    end

    it "raises when neither Cawfile nor .acd.cr exists" do
      Dir.mktmpdir do |root|
        workflow_dir = File.join(root, "empty")
        Dir.mkdir(workflow_dir)
        locator = ACD::Discovery::WorkflowLocator.new(root)
        expect_raises(Exception) { locator.resolve("empty") }
      end
    end
  end
end
