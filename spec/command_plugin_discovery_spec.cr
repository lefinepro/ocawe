require "./spec_helper"
require "file_utils"

describe "command plugin discovery" do
  it "discovers recursive Crystal plugins in lexical order" do
    root = File.tempname("command_plugins")
    Dir.mkdir_p(File.join(root, "plugins", "commands", "nested"))
    File.write(File.join(root, "Cawfile"), <<-CAW)
workflow "commands" do
  agent "noop"
end
CAW
    File.write(File.join(root, "plugins", "commands", "zeta.cr"), "# zeta\n")
    File.write(File.join(root, "plugins", "commands", "nested", "alpha.cr"), "# alpha\n")

    bundle = ACD::Discovery::CawfileLoader.load(root, "commands").not_nil!
    files = bundle.crystal_loader.not_nil!.registry_files

    files.should eq([
      File.realpath(File.join(root, "plugins", "commands", "nested", "alpha.cr")),
      File.realpath(File.join(root, "plugins", "commands", "zeta.cr")),
    ])
  ensure
    FileUtils.rm_rf(root) if root
  end

  it "keeps missing and empty plugin directories compatible" do
    root = File.tempname("command_plugins_empty")
    Dir.mkdir_p(root)
    File.write(File.join(root, "Cawfile"), "workflow \"commands\" do\n  agent \"noop\"\nend\n")

    bundle = ACD::Discovery::CawfileLoader.load(root, "commands").not_nil!
    bundle.crystal_loader.not_nil!.registry_files.should be_empty

    Dir.mkdir_p(File.join(root, "plugins", "commands"))
    bundle = ACD::Discovery::CawfileLoader.load(root, "commands").not_nil!
    bundle.crystal_loader.not_nil!.registry_files.should be_empty
  ensure
    FileUtils.rm_rf(root) if root
  end

  it "rejects a plugin symlink whose target escapes the project root" do
    root = File.tempname("command_plugins_root")
    outside = File.tempname("command_plugins_outside")
    Dir.mkdir_p(File.join(root, "plugins", "commands"))
    File.write(File.join(root, "Cawfile"), "workflow \"commands\" do\n  agent \"noop\"\nend\n")
    File.write(outside, "# outside\n")
    File.symlink(outside, File.join(root, "plugins", "commands", "outside.cr"))

    expect_raises(Exception, /escapes project root/) do
      ACD::Discovery::CawfileLoader.load(root, "commands")
    end
  ensure
    FileUtils.rm_rf(root) if root
    File.delete(outside) if outside && File.exists?(outside)
  end
end
