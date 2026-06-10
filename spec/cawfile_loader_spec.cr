require "./spec_helper"
require "file_utils"
require "../src/framework/discovery/cawfile_loader"

describe ACD::Discovery::CawfileLoader do
  describe ".find_cawfile" do
    it "finds Cawfile in directory" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), "workflow \"test\" do\nend\n")
        path = ACD::Discovery::CawfileLoader.find_cawfile(dir)
        path.should_not be_nil
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "finds .caw fallback in directory" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, ".caw"), "workflow \"test\" do\nend\n")
        path = ACD::Discovery::CawfileLoader.find_cawfile(dir)
        path.should_not be_nil
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "returns nil when neither exists" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        path = ACD::Discovery::CawfileLoader.find_cawfile(dir)
        path.should be_nil
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end

  describe ".load" do
    it "parses a minimal Cawfile with workflow and settings" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
settings do
  port = 4111
end

workflow "my-workflow" do
  follow ["@user@example.com"]
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "my-workflow")
        bundle.should_not be_nil
        bundle.not_nil!.id.should eq("my-workflow")
        bundle.not_nil!.follow.should eq(["@user@example.com"])
        bundle.not_nil!.start_settings["port"].should eq(4111)
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "extracts import paths" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
import = [
  "./workflows/*.acd.cr",
  "./workflows/*.rcl"
]

workflow "import-test" do
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "import-test")
        bundle.should_not be_nil
        bundle.not_nil!.import_paths.should eq(["./workflows/*.acd.cr", "./workflows/*.rcl"])
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "extracts DSL body from workflow block" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
workflow "dsl-test" do
  agent_codex
  follow ["@agent@example.com"]
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "dsl-test")
        bundle.not_nil!.id.should eq("dsl-test")
        dsl = bundle.not_nil!.dsl_source
        dsl.should_not be_nil
        dsl.not_nil!.size.should be > 0
        dsl.not_nil!.join.should contain("agent_codex")
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "parses dot-notation keys in settings" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
settings do
  data.adapter = "memory"
end

workflow "dot-test" do
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "dot-test")
        bundle.should_not be_nil
        bundle.not_nil!.config_datasets["adapter"].should eq("memory")
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "parses nested settings blocks" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
settings do
  federation do
    auto_subscribe = ["@user@example.com"]
  end
end

workflow "nested-test" do
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "nested-test")
        bundle.should_not be_nil
        bundle.not_nil!.config_federation["auto_subscribe"].should eq(["@user@example.com"])
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "returns nil when no workflow block exists" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
settings do
  port = 8080
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "test")
        bundle.should be_nil
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "extracts packages from @[Packages(...)] annotation" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
@[Packages(["git", "curl", "jq"])]
workflow "pkg-test" do
  agent_codex
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "pkg-test")
        bundle.should_not be_nil
        bundle.not_nil!.packages.should eq(["git", "curl", "jq"])
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "detects federation from Api::Federation::Inbox usage" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
struct Input
  include Api::Federation::Inbox
end

workflow "fed-test" do
  agent_codex
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "fed-test")
        bundle.should_not be_nil
        bundle.not_nil!.enable_federation.should be_true
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "detects federation from Api::Federation::Outbox usage" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
struct Output
  include Api::Federation::Outbox
end

workflow "fed-test" do
  agent_codex
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "fed-test")
        bundle.should_not be_nil
        bundle.not_nil!.enable_federation.should be_true
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end

  describe ".load_root" do
    it "parses root config without workflow block" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
settings do
  port = 9000
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load_root(dir)
        bundle.should_not be_nil
        bundle.not_nil!.id.should eq("root")
        bundle.not_nil!.start_settings["port"].should eq(9000)
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "parses root config with workflow block" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
settings do
  port = 9000
end

workflow "root-workflow" do
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load_root(dir)
        bundle.should_not be_nil
        bundle.not_nil!.id.should eq("root-workflow")
        bundle.not_nil!.start_settings["port"].should eq(9000)
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "returns nil when no Cawfile exists" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        bundle = ACD::Discovery::CawfileLoader.load_root(dir)
        bundle.should be_nil
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end
end
