require "./spec_helper"
require "tempfile"
require "../src/framework/discovery/cawfile_loader"

describe ACD::Discovery::CawfileLoader do
  describe ".find_cawfile" do
    it "finds Cawfile in directory" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "Cawfile"), "id = \"test\"")
        path = ACD::Discovery::CawfileLoader.find_cawfile(dir)
        path.should_not be_nil
      end
    end

    it "finds .caw fallback in directory" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".caw"), "id = \"test\"")
        path = ACD::Discovery::CawfileLoader.find_cawfile(dir)
        path.should_not be_nil
      end
    end

    it "returns nil when neither exists" do
      Dir.mktmpdir do |dir|
        path = ACD::Discovery::CawfileLoader.find_cawfile(dir)
        path.should be_nil
      end
    end
  end

  describe ".load" do
    it "parses a minimal Cawfile" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "Cawfile"), <<-RCL)
          id = "my-workflow"
          description = "A test workflow"
          version = "1.0.0"
        RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "my-workflow")
        bundle.should_not be_nil
        bundle.not_nil!.id.should eq("my-workflow")
        bundle.not_nil!.description.should eq("A test workflow")
        bundle.not_nil!.version.should eq("1.0.0")
      end
    end

    it "parses nix packages" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "Cawfile"), <<-RCL)
          id = "nix-test"
          packages do
            nix = ["git", "ruby"]
          end
        RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "nix-test")
        bundle.should_not be_nil
        bundle.not_nil!.nix_packages.should eq(["git", "ruby"])
      end
    end

    it "parses docker config" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "Cawfile"), <<-RCL)
          id = "docker-test"
          docker do
            from = "alpine:latest"
            install_nix = false
            expose = [8080, 9090]
            cmd = ["server"]
            env do
              PORT = "8080"
            end
            copy_paths = ["src", "bin"]
            build_commands = ["shards build"]
          end
        RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "docker-test")
        bundle.should_not be_nil
        cfg = bundle.not_nil!.docker_config
        cfg.from.should eq("alpine:latest")
        cfg.install_nix.should be_false
        cfg.expose.should eq([8080, 9090])
        cfg.cmd.should eq(["server"])
        cfg.env.should eq({"PORT" => "8080"})
        cfg.copy_paths.should eq(["src", "bin"])
        cfg.build_commands.should eq(["shards build"])
      end
    end

    it "parses workflow steps" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "Cawfile"), <<-RCL)
          id = "workflow-test"
          workflow do
            steps = [
              { type = "agent", id = "my-agent", model = "qwen3-coder" },
              { type = "exec", id = "my-exec", runtime = { command = "echo hello" } }
            ]
          end
        RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "workflow-test")
        bundle.should_not be_nil
        steps = bundle.not_nil!.workflow_steps
        steps.size.should eq(2)
        steps[0].type.should eq("agent")
        steps[0].id.should eq("my-agent")
        steps[1].type.should eq("exec")
        steps[1].id.should eq("my-exec")
      end
    end

    it "parses keys" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "Cawfile"), <<-RCL)
          id = "keys-test"
          keys = [
            { name = "OPENAI_API_KEY", required = true, description = "OpenAI API key", provider = "openai" },
            { name = "OPTIONAL_KEY", required = false }
          ]
        RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "keys-test")
        bundle.should_not be_nil
        keys = bundle.not_nil!.keys
        keys.size.should eq(2)
        keys[0].name.should eq("OPENAI_API_KEY")
        keys[0].required.should be_true
        keys[0].description.should eq("OpenAI API key")
        keys[0].provider.should eq("openai")
        keys[1].required.should be_false
      end
    end

    it "parses agents" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "Cawfile"), <<-RCL)
          id = "agents-test"
          agents = [
            { id = "reviewer", prompt = "Review code for issues", model = "qwen3-coder", description = "Code reviewer agent" }
          ]
        RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "agents-test")
        bundle.should_not be_nil
        agents = bundle.not_nil!.agents
        agents.size.should eq(1)
        agents[0].id.should eq("reviewer")
        agents[0].prompt.should eq("Review code for issues")
        agents[0].model.should eq("qwen3-coder")
        agents[0].description.should eq("Code reviewer agent")
      end
    end

    it "parses skills" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "Cawfile"), <<-RCL)
          id = "skills-test"
          skills = [
            { id = "healthcheck", name = "Health Check", description = "Check service health", file = "skills/healthcheck.md" }
          ]
        RCL
        bundle = ACD::Discovery::CawfileLoader.load(dir, "skills-test")
        bundle.should_not be_nil
        skills = bundle.not_nil!.skills
        skills.size.should eq(1)
        skills[0].id.should eq("healthcheck")
        skills[0].name.should eq("Health Check")
        skills[0].description.should eq("Check service health")
        skills[0].file.should eq("skills/healthcheck.md")
      end
    end
  end

  describe ".generate_dockerfile" do
    it "generates a Dockerfile with nix packages" do
      bundle = ACD::Discovery::CawfileBundle.new(
        id: "docker-test",
        nix_packages: ["git", "nodejs"],
        docker_config: ACD::Discovery::CawfileDockerConfig.new(
          from: "ubuntu:22.04",
          expose: [4111],
          cmd: ["./bin/ocawecore"]
        )
      )
      dockerfile = ACD::Discovery::CawfileLoader.generate_dockerfile(bundle)
      dockerfile.should contain("FROM ubuntu:22.04")
      dockerfile.should contain("Install Nix package manager")
      dockerfile.should contain("nix-env -iA nixpkgs.git nixpkgs.nodejs")
      dockerfile.should contain("EXPOSE 4111")
      dockerfile.should contain("CMD [\"./bin/ocawecore\"]")
    end

    it "generates a Dockerfile without nix when disabled" do
      bundle = ACD::Discovery::CawfileBundle.new(
        id: "docker-test",
        docker_config: ACD::Discovery::CawfileDockerConfig.new(
          from: "alpine:latest",
          install_nix: false,
          cmd: ["sh"]
        )
      )
      dockerfile = ACD::Discovery::CawfileLoader.generate_dockerfile(bundle)
      dockerfile.should_not contain("Install Nix")
    end
  end
end
