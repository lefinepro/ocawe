require "spec"
require "file_utils"
require "../src/framework/builder/nix_builder"

private class CommandPluginTestBuilder < Ocawe::Builder::NixBuilder
  def run_build_command(runtime : String, context : String, tag : String) : Bool
    true
  end
end

describe "command plugin container inclusion" do
  it "includes plugins omitted by an explicit file allowlist" do
    root = File.tempname("command_build")
    plugin_dir = File.join(root, "plugins", "commands")
    Dir.mkdir_p(plugin_dir)
    File.write(File.join(root, "Cawfile"), "workflow \"commands\" do\n  agent \"coder\"\nend\n")
    File.write(File.join(plugin_dir, "example.cr"), "# command source\n")

    builder = CommandPluginTestBuilder.new
    builder.build(
      "/bin/sh",
      context_dir: root,
      files: ["Cawfile"],
    ).should be_true

    copied = File.join(root, "build", "container", "rootfs", "app", "plugins", "commands", "example.cr")
    File.file?(copied).should be_true
  ensure
    FileUtils.rm_rf(root) if root
  end
end
