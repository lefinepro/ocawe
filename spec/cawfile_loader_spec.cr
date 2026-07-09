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

    it "extracts DSL body from workflow block" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
workflow "dsl-test" do
  agent "analyzer"
  follow ["@agent@example.com"]
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "dsl-test")
        bundle.not_nil!.id.should eq("dsl-test")
        dsl = bundle.not_nil!.dsl_source
        dsl.should_not be_nil
        dsl.not_nil!.size.should be > 0
        dsl.not_nil!.join.should contain("agent \"analyzer\"")
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "keeps workflow body lines after nested conditionals" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
workflow "conditional-dsl-test" do
  prepare
  if state.disposition == "queued"
    agent "planner-questions", model: "chat_completion/smallest"
  end
  finalize
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "conditional-dsl-test")
        dsl = bundle.not_nil!.dsl_source.not_nil!.join("\n")
        dsl.should contain("agent \"planner-questions\"")
        dsl.should contain("finalize")
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

    it "parses log_level from settings" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
settings do
  port = 4111
  log_level = "debug"
end

workflow "log-test" do
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "log-test")
        bundle.should_not be_nil
        bundle.not_nil!.start_settings["port"].should eq(4111)
        bundle.not_nil!.start_settings["log_level"].should eq("debug")
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "parses nested log block in settings" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
settings do
  log do
    level = "critical"
  end
end

workflow "nested-log-test" do
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "nested-log-test")
        bundle.should_not be_nil
        bundle.not_nil!.config_log["level"].should eq("critical")
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

    it "extracts container from root container block" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
container do
  packages = ["git", "curl", "jq"]
end

workflow "container-test" do
  agent "analyzer"
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "container-test")
        bundle.should_not be_nil
        container = bundle.not_nil!.container
        container.should_not be_nil
        container.not_nil!.mode.should eq(ACD::Discovery::ContainerMode::Nix)
        container.not_nil!.packages.should eq(["git", "curl", "jq"])
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "keeps legacy @[Container(...)] annotation compatible" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
@[Container(packages: ["git"])]
workflow "legacy-container-test" do
  agent "analyzer"
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "legacy-container-test")
        bundle.should_not be_nil
        container = bundle.not_nil!.container
        container.should_not be_nil
        container.not_nil!.mode.should eq(ACD::Discovery::ContainerMode::Nix)
        container.not_nil!.packages.should eq(["git"])
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "defaults container to static when no packages specified" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
container do
end

workflow "static-test" do
  agent "analyzer"
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "static-test")
        bundle.should_not be_nil
        container = bundle.not_nil!.container
        container.should_not be_nil
        container.not_nil!.mode.should eq(ACD::Discovery::ContainerMode::Static)
        container.not_nil!.packages.should be_empty
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
  agent "analyzer"
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
  agent "analyzer"
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "fed-test")
        bundle.should_not be_nil
        bundle.not_nil!.enable_federation.should be_true
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "extracts @[Validate(...)] annotations" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
struct InputSimple
  include Api::OpenResponses::Request
end

struct OutputSimple
  include Api::OpenResponses::Response
end

@[Validate(InputSimple, OutputSimple)]
workflow "validate-test" do
  agent "analyzer"
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "validate-test")
        bundle.should_not be_nil
        bundle.not_nil!.input_type.should eq("InputSimple")
        bundle.not_nil!.output_type.should eq("OutputSimple")
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "extracts @[Model(...)] string annotation" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
@[Model("openai/gpt-4.1")]
workflow "model-test" do
  agent "analyzer"
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "model-test")
        bundle.should_not be_nil
        bundle.not_nil!.model.should eq("openai/gpt-4.1")
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "resolves @[Model(...)] class annotation against @.meta/models.json" do
      dir = File.tempname("cawfile_test")
      meta_dir = File.join(dir, ".meta")
      Dir.mkdir_p(meta_dir)
      begin
        File.write(File.join(meta_dir, "models.json"), <<-JSON)
{
  "models": {
    "GPT4": {
      "provider": "openai",
      "version": "4.1",
      "model": "gpt-4.1"
    }
  }
}
JSON
        File.write(File.join(dir, "Cawfile"), <<-RCL)
@[Validate(Input, Output)]
@[Model(GPT4)]
workflow "model-json-test" do
  agent "analyzer"
end
RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "model-json-test")
        bundle.should_not be_nil
        bundle.not_nil!.model.should eq("openai/gpt-4.1")
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "loads multiple root workflows and marks service workflows" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
settings do
  port = 4111
end

@[Service]
@[Validate(Input, Output)]
workflow "shared-service" do
  exec "boot", runtime: {shell: "bash"}
end

@[Validate(Input, Output)]
workflow "chat-task" do
  follow ["@fmatch.example"]
  exec "codex", runtime: {acp: {command: "codex"}}
end
RCL
        bundles = ACD::Discovery::CawfileLoader.load_all(dir)
        bundles.map(&.id).should eq(["shared-service", "chat-task"])
        bundles[0].service.should eq(true)
        bundles[1].service.should eq(false)
        bundles[0].start_settings["port"].should eq(4111)
        bundles[1].follow.should eq(["@fmatch.example"])

        ACD::Discovery::CawfileLoader.load(dir, "chat-task").not_nil!.id.should eq("chat-task")
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "keeps nested dataset and loop blocks inside the owning workflow slice" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), <<-RCL)
@[Validate(Input, Output)]
workflow "with-nested-blocks" do
  dataset "profiles" do
    description "Profiles"
  end
  loop do
    exec "tick", runtime: {shell: "bash"}
  end
end

@[Validate(Input, Output)]
workflow "next-workflow" do
  exec "next", runtime: {shell: "bash"}
end
RCL
        bundles = ACD::Discovery::CawfileLoader.load_all(dir)
        bundles.map(&.id).should eq(["with-nested-blocks", "next-workflow"])

        first_source = bundles[0].dsl_source.not_nil!.join("\n")
        first_source.should contain("dataset \"profiles\"")
        first_source.should contain("loop do")
        first_source.should contain("exec \"tick\"")
        first_source.should_not contain("workflow \"next-workflow\"")

        bundles[1].dsl_source.not_nil!.join("\n").should contain("exec \"next\"")
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
