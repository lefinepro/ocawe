require "./spec_helper"
require "file_utils"

def run_fs_agent(root : String, write_policy : String = "write", env : Hash(String, String) = {} of String => String)
  agent = File.expand_path("support/fs_acp_agent.cr", __DIR__)
  policy = ACP::Client::FilesystemPolicy.new(root, write_policy)
  client = ACP::Client.new("crystal", ["run", agent], env, policy)
  client.start
  client.create_session(root)
  result = client.prompt("exercise fs")
  updates = client.collect_updates
  client.close
  {result, updates}
end

describe ACP::Client do
  it "handles ACP writeTextFile and readTextFile inside the workspace" do
    dir = File.tempname("ocawe-acp-fs")
    Dir.mkdir_p(dir)

    begin
      result, updates = run_fs_agent(dir, env: {
        "ACP_FS_PATH"    => "nested/sentinel.txt",
        "ACP_FS_CONTENT" => "created by acp",
      })

      result.stopReason.should eq("end_turn")
      File.read(File.join(dir, "nested", "sentinel.txt")).should eq("created by acp")
      updates.map { |update| update.update.content.try(&.text).to_s }.join.should contain("created by acp")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "rejects writes outside the workspace" do
    dir = File.tempname("ocawe-acp-fs")
    Dir.mkdir_p(dir)

    begin
      _result, updates = run_fs_agent(dir, env: {
        "ACP_FS_MODE" => "write-only",
        "ACP_FS_PATH" => "../escaped.txt",
      })

      File.exists?(File.expand_path("../escaped.txt", dir)).should be_false
      updates.map { |update| update.update.content.try(&.text).to_s }.join.should contain("path escapes workspace")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "rejects writes when the workspace is read-only" do
    dir = File.tempname("ocawe-acp-fs")
    Dir.mkdir_p(dir)

    begin
      _result, updates = run_fs_agent(dir, "read_only", env: {
        "ACP_FS_MODE" => "write-only",
        "ACP_FS_PATH" => "blocked.txt",
      })

      File.exists?(File.join(dir, "blocked.txt")).should be_false
      updates.map { |update| update.update.content.try(&.text).to_s }.join.should contain("workspace is read-only")
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
