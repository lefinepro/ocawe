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
      it "parses container with image, packages, and files" do
        dir = File.tempname("cawfile_test")
        Dir.mkdir_p(dir)
        begin
          File.write(File.join(dir, "Cawfile"), <<-RCL)
@[Container(
  image: "docker.io/library/debian",
  packages: ["git", "curl", "jq"],
  files: ["script.sh", "config.json"]
)]
workflow "container-test" do
  agent "analyzer"
end
RCL
          bundle = CawfileLoader.load(dir, "container-test")
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

      it "defaults files to all files in directory when not specified" do
        dir = File.tempname("cawfile_test")
        Dir.mkdir_p(dir)
        begin
          File.write(File.join(dir, "Cawfile"), <<-RCL)
@[Container(packages: ["nginx"])]
workflow "files-default-test" do
  agent "analyzer"
end
RCL
          bundle = CawfileLoader.load(dir, "files-default-test")
          bundle.should_not be_nil
          container = bundle.not_nil!.container
          container.should_not be_nil
          container.not_nil!.files.should be_empty
          # Note: actual file resolution happens at build time
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

      it "does not parse deprecated mode parameter" do
        dir = File.tempname("cawfile_test")
        Dir.mkdir_p(dir)
        begin
          File.write(File.join(dir, "Cawfile"), <<-RCL)
@[Container(mode: "nix", packages: ["git"])]
workflow "deprecated-mode-test" do
  agent "analyzer"
end
RCL
          bundle = CawfileLoader.load(dir, "deprecated-mode-test")
          bundle.should_not be_nil
          container = bundle.not_nil!.container
          container.should_not be_nil
          container.not_nil!.packages.should eq(["git"])
          # mode is no longer a thing, should still parse other fields
        ensure
          FileUtils.rm_rf(dir)
        end
      end

      it "returns nil container when no @[Container] annotation" do
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
      it "generates multi-stage nix build with scratch final by default" do
        builder = NixBuilder.new
        dockerfile = builder.generate_dockerfile(
          image: nil,
          packages: ["git", "curl"],
          files: ["script.sh", "data.json"]
        )
        dockerfile.should contain("FROM nixos/nix")
        dockerfile.should contain("FROM scratch")
        dockerfile.should contain("pkgsStatic")
        dockerfile.should contain("git")
        dockerfile.should contain("curl")
        dockerfile.should contain("COPY script.sh")
        dockerfile.should contain("COPY data.json")
        dockerfile.should contain("COPY ocawecore")
        dockerfile.should contain("ENTRYPOINT [\"/app/ocawecore\"]")
        dockerfile.should contain("COPY --from=nix-build")
      end

      it "generates multi-stage nix build with custom image final" do
        builder = NixBuilder.new
        dockerfile = builder.generate_dockerfile(
          image: "docker.io/library/debian",
          packages: ["jq"],
          files: ["data.csv"]
        )
        dockerfile.should contain("FROM nixos/nix")
        dockerfile.should contain("FROM docker.io/library/debian")
        dockerfile.should contain("COPY data.csv")
        dockerfile.should_not contain("FROM scratch")
      end

      it "generates no packages when packages is empty" do
        builder = NixBuilder.new
        dockerfile = builder.generate_dockerfile(
          image: nil,
          packages: [] of String,
          files: [] of String
        )
        dockerfile.should contain("FROM nixos/nix")
        dockerfile.should contain("FROM scratch")
        dockerfile.should_not contain("nix-env")
      end

      it "generates nix expression with pkgsStatic for static builds" do
        builder = NixBuilder.new
        dockerfile = builder.generate_dockerfile(
          image: nil,
          packages: ["htop", "ripgrep"],
          files: [] of String
        )
        dockerfile.should contain("pkgsStatic")
        dockerfile.should contain("htop")
        dockerfile.should contain("ripgrep")
      end

      it "generates find-based COPY for nix store closure" do
        builder = NixBuilder.new
        dockerfile = builder.generate_dockerfile(
          image: nil,
          packages: ["git"],
          files: ["script.sh"]
        )
        dockerfile.should contain("nix-store -q --requisites")
        dockerfile.should contain("xargs -I {} cp -r")
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

          context = File.join(dir, "build")
          File.file?(File.join(context, "ocawecore")).should be_true
          File.file?(File.join(context, "script.sh")).should be_true
          File.file?(File.join(context, "data.json")).should be_true
        ensure
          FileUtils.rm_rf(dir)
        end
      end
    end
  end
end
