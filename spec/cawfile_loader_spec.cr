require "./spec_helper"
require "file_utils"
require "../src/framework/discovery/cawfile_loader"

describe ACD::Discovery::CawfileLoader do
  describe ".find_cawfile" do
    it "finds Cawfile in directory" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), "id = \"test\"")
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
        File.write(File.join(dir, ".caw"), "id = \"test\"")
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
    it "parses a minimal Cawfile" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), "workflow \"my-workflow\" do\n  version = \"1.0.0\"\n  description = \"A test workflow\"\nend\n")
        bundle = ACD::Discovery::CawfileLoader.load(dir, "my-workflow")
        bundle.should_not be_nil
        bundle.not_nil!.id.should eq("my-workflow")
        bundle.not_nil!.description.should eq("A test workflow")
        bundle.not_nil!.version.should eq("1.0.0")
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "parses packages array" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), "workflow \"pkg-test\" do\n  packages = [\"git\", \"ruby\"]\nend\n")
        bundle = ACD::Discovery::CawfileLoader.load(dir, "pkg-test")
        bundle.should_not be_nil
        bundle.not_nil!.packages.should eq(["git", "ruby"])
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "parses keys" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), "workflow \"keys-test\" do\n  key \"OPENAI_API_KEY\" do\n    required = true\n    description = \"OpenAI API key\"\n    provider = \"openai\"\n  end\n  key \"OPTIONAL_KEY\" do\n    required = false\n  end\nend\n")
        bundle = ACD::Discovery::CawfileLoader.load(dir, "keys-test")
        bundle.should_not be_nil
        keys = bundle.not_nil!.keys
        keys.size.should eq(2)
        keys[0].name.should eq("OPENAI_API_KEY")
        keys[0].required.should be_true
        keys[0].description.should eq("OpenAI API key")
        keys[0].provider.should eq("openai")
        keys[1].required.should be_false
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "parses agents" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), "workflow \"agents-test\" do\n  agent \"reviewer\" do\n    prompt = \"Review code\"\n    model = \"qwen3-coder\"\n    description = \"Code reviewer agent\"\n  end\nend\n")
        bundle = ACD::Discovery::CawfileLoader.load(dir, "agents-test")
        bundle.should_not be_nil
        agents = bundle.not_nil!.agents
        agents.size.should eq(1)
        agents[0].id.should eq("reviewer")
        agents[0].prompt.should eq("Review code")
        agents[0].model.should eq("qwen3-coder")
        agents[0].description.should eq("Code reviewer agent")
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "parses skills" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), "workflow \"skills-test\" do\n  skill \"healthcheck\" do\n    name = \"Health Check\"\n    description = \"Check service health\"\n    file = \"skills/healthcheck.md\"\n  end\nend\n")
        bundle = ACD::Discovery::CawfileLoader.load(dir, "skills-test")
        bundle.should_not be_nil
        skills = bundle.not_nil!.skills
        skills.size.should eq(1)
        skills[0].id.should eq("healthcheck")
        skills[0].name.should eq("Health Check")
        skills[0].description.should eq("Check service health")
        skills[0].file.should eq("skills/healthcheck.md")
      ensure
        FileUtils.rm_rf(dir)
      end
    end

    it "parses steps" do
      dir = File.tempname("cawfile_test")
      Dir.mkdir_p(dir)
      begin
        File.write(File.join(dir, "Cawfile"), "workflow \"steps-test\" do\n  step \"agent-check\" do\n    model = \"qwen3-coder\"\n  end\n  step \"exec-deploy\" do\n    command = \"./scripts/deploy.sh\"\n  end\nend\n")
        bundle = ACD::Discovery::CawfileLoader.load(dir, "steps-test")
        bundle.should_not be_nil
        steps = bundle.not_nil!.workflow_steps
        steps.size.should eq(2)
        steps[0].type.should eq("agent")
        steps[0].id.should eq("check")
        steps[0].params.has_key?("model").should be_true
        steps[1].type.should eq("exec")
        steps[1].id.should eq("deploy")
        steps[1].params.has_key?("command").should be_true
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end
end
