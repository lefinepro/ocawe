require "spec"
require "file_utils"
require "../src/framework/discovery/cawfile_loader"
require "../src/framework/builder/nix_builder"

SPEC_TEMP_DIR = File.tempname("ocawe_spec")

class Spec::GlobalContext
  @@temp_dirs = [] of String

  def self.track(dir : String)
    @@temp_dirs << dir
  end

  def self.cleanup
    @@temp_dirs.each { |d| FileUtils.rm_rf(d) }
    @@temp_dirs.clear
  end
end

Spec.after_suite { Spec::GlobalContext.cleanup }

module ACD::Discovery
  describe CawfileLoader do
    describe "#load" do
      it "parses root container block with packages and files" do
        dir = File.tempname("cawfile_test")
        Dir.mkdir_p(dir)
        begin
          File.write(File.join(dir, "Cawfile"), <<-RCL)
container do
  packages = ["git", "curl", "jq", "github:owner/tool", "./local-tool"]
  files = ["script.sh", "config.json"]
end

workflow "container-test" do
  agent "analyzer"
end
RCL
          bundle = CawfileLoader.load(dir, "container-test")
          bundle.should_not be_nil
          container = bundle.not_nil!.container
          container.should_not be_nil
          container.not_nil!.image.should be_nil
          container.not_nil!.mode.should eq(ContainerMode::Nix)
          container.not_nil!.packages.should eq(["git", "curl", "jq", "github:owner/tool", "./local-tool"])
          container.not_nil!.files.should eq(["script.sh", "config.json"])
        ensure
          FileUtils.rm_rf(dir)
        end
      end

      it "keeps files optional in root container blocks" do
        dir = File.tempname("cawfile_test")
        Dir.mkdir_p(dir)
        begin
          File.write(File.join(dir, "Cawfile"), <<-RCL)
container do
  packages = ["nginx"]
end

workflow "files-default-test" do
  agent "analyzer"
end
RCL
          bundle = CawfileLoader.load(dir, "files-default-test")
          bundle.should_not be_nil
          container = bundle.not_nil!.container
          container.should_not be_nil
          container.not_nil!.files.should be_empty
          # Empty files means actual file resolution happens at build time.
        ensure
          FileUtils.rm_rf(dir)
        end
      end

      it "keeps legacy container annotations compatible" do
        dir = File.tempname("cawfile_test")
        Dir.mkdir_p(dir)
        begin
          File.write(File.join(dir, "Cawfile"), <<-RCL)
@[Container(
  image: "docker.io/library/debian",
  packages: ["git", "curl", "jq"],
  files: ["script.sh", "config.json"]
)]
workflow "legacy-container-test" do
  agent "analyzer"
end
RCL
          bundle = CawfileLoader.load(dir, "legacy-container-test")
          bundle.should_not be_nil
          container = bundle.not_nil!.container
          container.should_not be_nil
          container.not_nil!.image.should eq("docker.io/library/debian")
          container.not_nil!.packages.should eq(["git", "curl", "jq"])
          container.not_nil!.files.should eq(["script.sh", "config.json"])
        ensure
          FileUtils.rm_rf(dir)
        end
      end

      it "defaults image to nil (scratch) when not specified" do
        dir = File.tempname("cawfile_test")
        Dir.mkdir_p(dir)
        begin
          File.write(File.join(dir, "Cawfile"), <<-RCL)
@[Container(packages: ["htop"])]
workflow "scratch-test" do
  agent "analyzer"
end
RCL
          bundle = CawfileLoader.load(dir, "scratch-test")
          bundle.should_not be_nil
          container = bundle.not_nil!.container
          container.should_not be_nil
          container.not_nil!.image.should be_nil
        ensure
          FileUtils.rm_rf(dir)
        end
      end

      it "parses container with only image specified" do
        dir = File.tempname("cawfile_test")
        Dir.mkdir_p(dir)
        begin
          File.write(File.join(dir, "Cawfile"), <<-RCL)
@[Container(image: "alpine:latest")]
workflow "image-only-test" do
  agent "analyzer"
end
RCL
          bundle = CawfileLoader.load(dir, "image-only-test")
          bundle.should_not be_nil
          container = bundle.not_nil!.container
          container.should_not be_nil
          container.not_nil!.image.should eq("alpine:latest")
          container.not_nil!.packages.should be_empty
          container.not_nil!.files.should be_empty
        ensure
          FileUtils.rm_rf(dir)
        end
      end

      it "ignores legacy mode parameter" do
        dir = File.tempname("cawfile_test")
        Dir.mkdir_p(dir)
        begin
          File.write(File.join(dir, "Cawfile"), <<-RCL)
@[Container(mode: "nix")]
workflow "deprecated-mode-test" do
  agent "analyzer"
end
RCL
          bundle = CawfileLoader.load(dir, "deprecated-mode-test")
          bundle.should_not be_nil
          container = bundle.not_nil!.container
          container.should_not be_nil
          container.not_nil!.mode.should eq(ContainerMode::Static)
          container.not_nil!.packages.should be_empty
        ensure
          FileUtils.rm_rf(dir)
        end
      end

      it "returns nil container when no container configuration exists" do
        dir = File.tempname("cawfile_test")
        Dir.mkdir_p(dir)
        begin
          File.write(File.join(dir, "Cawfile"), <<-RCL)
workflow "no-container-test" do
  agent "analyzer"
end
RCL
          bundle = CawfileLoader.load(dir, "no-container-test")
          bundle.should_not be_nil
          bundle.not_nil!.container.should be_nil
        ensure
          FileUtils.rm_rf(dir)
        end
      end

      it "loads the full-suite example with container config and service workflows" do
        bundles = CawfileLoader.load_all("caws/06-full-suite")
        bundles.map(&.id).should eq([
          "06-full-suite",
          "06-full-suite-daemon",
          "06-full-suite-watch",
        ])

        service_ids = bundles.select(&.service).map(&.id)
        service_ids.should eq(["06-full-suite-daemon", "06-full-suite-watch"])

        bundles.each do |bundle|
          container = bundle.container
          container.should_not be_nil
          container.not_nil!.packages.should eq(["git", "curl", "jq"])
          container.not_nil!.files.should eq(["agents", "skills", "tools"])
          container.not_nil!.mode.should eq(ContainerMode::Nix)
        end
      end
    end
  end
end

module Ocawe::Builder
  class TestNixBuilder < NixBuilder
    def run_build_command(runtime : String, context : String, tag : String) : Bool
      true # skip docker invocation in tests
    end
  end

  describe NixBuilder do
    describe "#generate_dockerfile" do
      it "generates a fast rootfs image with scratch final by default" do
        builder = NixBuilder.new
        dockerfile = builder.generate_dockerfile(
          image: nil,
          packages: ["git", "curl"],
          files: ["script.sh", "data.json"]
        )
        dockerfile.should contain("FROM scratch")
        dockerfile.should contain("COPY rootfs/ /")
        dockerfile.should contain("WORKDIR /app")
        dockerfile.should contain("ENV SSL_CERT_FILE=\"/etc/ssl/certs/ca-bundle.crt\"")
        dockerfile.should contain("ENTRYPOINT [\"/usr/lib/ld-linux-x86-64.so.2\", \"--library-path\", \"/usr/lib:/lib\", \"/app/ocawecore\"]")
        dockerfile.should_not contain("nix-channel")
        dockerfile.should_not contain("nix-env")
      end

      it "generates a fast rootfs image with custom image final" do
        builder = NixBuilder.new
        dockerfile = builder.generate_dockerfile(
          image: "docker.io/library/debian",
          packages: ["jq"],
          files: ["data.csv"]
        )
        dockerfile.should contain("FROM docker.io/library/debian")
        dockerfile.should contain("COPY rootfs/ /")
        dockerfile.should_not contain("FROM scratch")
        dockerfile.should_not contain("nix-channel")
      end

      it "generates no packages when packages is empty" do
        builder = NixBuilder.new
        dockerfile = builder.generate_dockerfile(
          image: nil,
          packages: [] of String,
          files: [] of String
        )
        dockerfile.should contain("FROM scratch")
        dockerfile.should contain("COPY rootfs/ /")
        dockerfile.should_not contain("nix-env")
      end

      it "does not install packages during docker build" do
        builder = NixBuilder.new
        dockerfile = builder.generate_dockerfile(
          image: nil,
          packages: ["htop", "ripgrep"],
          files: [] of String
        )
        dockerfile.should_not contain("pkgsStatic")
        dockerfile.should_not contain("htop")
        dockerfile.should_not contain("ripgrep")
        dockerfile.should_not contain("nix profile install")
      end

      it "keeps flake and path package refs out of dockerfile commands" do
        builder = NixBuilder.new
        dockerfile = builder.generate_dockerfile(
          image: nil,
          packages: ["git", "github:owner/tool", "./local-tool", "/opt/tool"],
          files: [] of String
        )
        dockerfile.should_not contain("github:owner/tool")
        dockerfile.should_not contain("./local-tool")
        dockerfile.should_not contain("/opt/tool")
        dockerfile.should_not contain("nix profile install")
      end

      it "copies a prepared rootfs instead of generating nix store commands" do
        builder = NixBuilder.new
        dockerfile = builder.generate_dockerfile(
          image: nil,
          packages: ["git"],
          files: ["script.sh"]
        )
        dockerfile.should contain("COPY rootfs/ /")
        dockerfile.should_not contain("nix-store -q --requisites")
        dockerfile.should_not contain("xargs -I {} cp -r")
      end
    end

    describe "#build" do
      it "passes container config to the builder" do
        # This is an integration-level check; actual build requires docker/nix
        builder = NixBuilder.new
        builder.should be_a(Builder)
      end

      it "copies all directory files into build context when files is empty" do
        dir = File.tempname("nixbuilder_test")
        Dir.mkdir_p(dir)
        begin
          # Create fake binary and extra files
          bin_path = File.join(dir, "ocawecore")
          File.write(bin_path, "fake binary")
          File.write(File.join(dir, "script.sh"), "#!/bin/bash\necho hello")
          File.write(File.join(dir, "data.json"), "{}")
          Dir.mkdir_p(File.join(dir, "agents"))
          File.write(File.join(dir, "agents", "assistant.md"), "---\nname: Assistant\n---\n")

          # Use a test subclass to skip docker invocation
          test_builder = TestNixBuilder.new
          test_builder.build(
            bin_path,
            tag: "test",
            context_dir: dir,
            runtime: "docker",
            image: nil,
            packages: [] of String,
            files: [] of String
          )

          context = File.join(dir, "build", "container")
          File.file?(File.join(context, "rootfs", "app", "ocawecore")).should be_true
          File.file?(File.join(context, "rootfs", "app", "script.sh")).should be_true
          File.file?(File.join(context, "rootfs", "app", "data.json")).should be_true
          File.file?(File.join(context, "rootfs", "app", "agents", "assistant.md")).should be_true
        ensure
          FileUtils.rm_rf(dir)
        end
      end

      it "copies root .caw config even though hidden files are excluded by default" do
        dir = File.tempname("nixbuilder_test")
        Dir.mkdir_p(dir)
        begin
          bin_path = File.join(dir, "ocawecore")
          File.write(bin_path, "fake binary")
          File.write(File.join(dir, ".caw"), "workflow \"hidden-caw\" do\nend\n")
          File.write(File.join(dir, ".env"), "SHOULD_NOT_COPY=1\n")

          test_builder = TestNixBuilder.new
          test_builder.build(
            bin_path,
            tag: "test",
            context_dir: dir,
            runtime: "docker",
            image: nil,
            packages: [] of String,
            files: [] of String
          )

          context = File.join(dir, "build", "container")
          File.file?(File.join(context, "rootfs", "app", ".caw")).should be_true
          File.file?(File.join(context, "rootfs", "app", ".env")).should be_false
        ensure
          FileUtils.rm_rf(dir)
        end
      end

      it "falls back to a rootfs archive when runtime command is not usable" do
        dir = File.tempname("nixbuilder_test")
        fake_bin = File.tempname("nixbuilder_fake_runtime")
        Dir.mkdir_p(dir)
        Dir.mkdir_p(fake_bin)
        old_path = ENV["PATH"]?
        begin
          bin_path = File.join(dir, "ocawecore")
          File.write(bin_path, "fake binary")

          runtime_path = File.join(fake_bin, "fake-runtime")
          File.write(runtime_path, <<-SH)
          #!/bin/sh
          if [ "$1" = "info" ]; then
            exit 1
          fi
          touch "#{File.join(dir, "runtime-used")}"
          exit 0
          SH
          File.chmod(runtime_path, 0o755)
          ENV["PATH"] = "#{fake_bin}:#{old_path}"

          builder = NixBuilder.new
          builder.build(
            bin_path,
            tag: "fallback:test",
            context_dir: dir,
            runtime: "fake-runtime",
            image: nil,
            packages: [] of String,
            files: [] of String
          ).should be_true

          File.exists?(File.join(dir, "runtime-used")).should be_false
          File.file?(File.join(dir, "build", "container", "fallback-test.rootfs.tar")).should be_true
        ensure
          if old = old_path
            ENV["PATH"] = old
          else
            ENV.delete("PATH")
          end
          FileUtils.rm_rf(dir)
          FileUtils.rm_rf(fake_bin)
        end
      end
    end
  end
end
