require "./spec_helper"
require "file_utils"

describe Ocawe::Workflow::ExecExecutor do
  it "rejects non-mcp refs without runtime" do
    executor = Ocawe::Workflow::ExecExecutor.new
    ctx = Ocawe::Workflow::NodeContext.new(
      workflow_id: "wf",
      run_id: "run_1",
      node_id: "create_sandbox",
      input_data: {} of String => JSON::Any,
      state: {} of String => JSON::Any,
    )

    expect_raises(Exception, /exec requires runtime/) do
      executor.exec("create_sandbox", ctx)
    end
  end

  it "runs external scripts with runtime metadata" do
    tmp_dir = File.tempname("sandbox-example")
    Dir.mkdir_p(File.join(tmp_dir, "tools"))
    script = File.join(tmp_dir, "tools", "create-sandbox.sh")
    File.write(script, "#!/usr/bin/env bash\nset -euo pipefail\necho '{\"status\":\"ok\"}'\n")
    File.chmod(script, 0o755)

    begin
      executor = Ocawe::Workflow::ExecExecutor.new
      ctx = Ocawe::Workflow::NodeContext.new(
        workflow_id: "wf",
        run_id: "run_2",
        node_id: "external-tool",
        input_data: {} of String => JSON::Any,
        state: {} of String => JSON::Any,
      )
      runtime = {"shell" => json_any("bash")} of String => JSON::Any

      result = executor.exec(
        "tools/create-sandbox.sh",
        ctx,
        runtime: runtime,
        workflow_root: tmp_dir,
      )
      result["status"].as_s.should eq("ok")
    ensure
      FileUtils.rm_rf(tmp_dir)
    end
  end

  it "fails when external run emits invalid json" do
    dir = "/tmp/ocawecore-test-tools"
    FileUtils.mkdir_p(dir)
    script = File.join(dir, "invalid.sh")
    File.write(script, "#!/usr/bin/env bash\nset -euo pipefail\necho not-json\n")
    File.chmod(script, 0o755)

    executor = Ocawe::Workflow::ExecExecutor.new
    ctx = Ocawe::Workflow::NodeContext.new(
      workflow_id: "wf",
      run_id: "run_3",
      node_id: "external-invalid",
      input_data: {} of String => JSON::Any,
      state: {} of String => JSON::Any,
    )

    runtime = {"shell" => json_any("bash")} of String => JSON::Any
    expect_raises(Exception, /invalid JSON/) do
      executor.exec("invalid.sh", ctx, runtime: runtime, workflow_root: dir)
    end
  end

  it "fails when runtime object is empty" do
    executor = Ocawe::Workflow::ExecExecutor.new
    ctx = Ocawe::Workflow::NodeContext.new(
      workflow_id: "wf",
      run_id: "run_4",
      node_id: "external-empty-runtime",
      input_data: {"task" => json_any("hello")},
      state: {"task" => json_any("hello")},
    )

    tmp_dir = File.tempname("sandbox-example")
    Dir.mkdir_p(File.join(tmp_dir, "tools"))
    script = File.join(tmp_dir, "tools", "create-sandbox.sh")
    File.write(script, "#!/usr/bin/env bash\nset -euo pipefail\necho '{\"status\":\"ok\"}'\n")
    File.chmod(script, 0o755)

    begin
      expect_raises(Exception, /runtime object must contain at least one key/) do
        executor.exec("tools/create-sandbox.sh", ctx, runtime: ({} of String => JSON::Any), workflow_root: tmp_dir)
      end
    ensure
      FileUtils.rm_rf(tmp_dir)
    end
  end

  it "auto-pulls git+https Cawfile refs" do
    tmp_dir = File.tempname("git-https-runtime")
    bin_dir = File.join(tmp_dir, "bin")
    cache_dir = File.join(tmp_dir, "cache")
    Dir.mkdir_p(bin_dir)
    fake_git = File.join(bin_dir, "git")
    File.write(fake_git, <<-SH)
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "clone" ]; then
  mkdir -p "$3/caws/10-acp-agent"
  printf 'workflow "10-acp-agent" do\\nend\\n' > "$3/caws/10-acp-agent/Cawfile"
  exit 0
fi
if [ "$1" = "-C" ]; then
  exit 0
fi
exit 1
SH
    File.chmod(fake_git, 0o755)

    old_path = ENV["PATH"]?
    old_cache = ENV["OCAWE_CACHE_DIR"]?
    ENV["PATH"] = "#{bin_dir}:#{old_path}"
    ENV["OCAWE_CACHE_DIR"] = cache_dir

    begin
      executor = Ocawe::Workflow::ExecExecutor.new
      ctx = Ocawe::Workflow::NodeContext.new(
        workflow_id: "wf",
        run_id: "run_git_https",
        node_id: "remote-caw",
        input_data: {} of String => JSON::Any,
        state: {} of String => JSON::Any,
      )
      runtime = {"git+https" => json_any(true)} of String => JSON::Any

      result = executor.exec(
        "git+https://github.com/lefinepro/ocawe/caws/10-acp-agent",
        ctx,
        runtime: runtime,
      )

      result["repo"].as_s.should eq("github.com/lefinepro/ocawe")
      result["transport"].as_s.should eq("git+https")
      result["local_path"].as_s.ends_with?("github.com/lefinepro/ocawe/caws/10-acp-agent").should eq(true)
      result["cawfile"].as_s.ends_with?("Cawfile").should eq(true)
      result["cloned"].as_bool.should eq(true)
    ensure
      if old_path
        ENV["PATH"] = old_path
      else
        ENV.delete("PATH")
      end
      if old_cache
        ENV["OCAWE_CACHE_DIR"] = old_cache
      else
        ENV.delete("OCAWE_CACHE_DIR")
      end
      FileUtils.rm_rf(tmp_dir)
    end
  end

  it "auto-pulls git+ssh Cawfile refs" do
    tmp_dir = File.tempname("git-ssh-runtime")
    bin_dir = File.join(tmp_dir, "bin")
    cache_dir = File.join(tmp_dir, "cache")
    clone_url_file = File.join(tmp_dir, "clone-url")
    Dir.mkdir_p(bin_dir)
    fake_git = File.join(bin_dir, "git")
    File.write(fake_git, <<-SH)
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "clone" ]; then
  printf '%s\\n' "$2" > "#{clone_url_file}"
  mkdir -p "$3/caws/10-acp-agent"
  printf 'workflow "10-acp-agent" do\\nend\\n' > "$3/caws/10-acp-agent/Cawfile"
  exit 0
fi
if [ "$1" = "-C" ]; then
  exit 0
fi
exit 1
SH
    File.chmod(fake_git, 0o755)

    old_path = ENV["PATH"]?
    old_cache = ENV["OCAWE_CACHE_DIR"]?
    ENV["PATH"] = "#{bin_dir}:#{old_path}"
    ENV["OCAWE_CACHE_DIR"] = cache_dir

    begin
      executor = Ocawe::Workflow::ExecExecutor.new
      ctx = Ocawe::Workflow::NodeContext.new(
        workflow_id: "wf",
        run_id: "run_git_ssh",
        node_id: "remote-caw",
        input_data: {} of String => JSON::Any,
        state: {} of String => JSON::Any,
      )
      runtime = {"git+ssh" => json_any(true)} of String => JSON::Any

      result = executor.exec(
        "git+ssh://github.com/lefinepro/ocawe/caws/10-acp-agent/10-acp-agent",
        ctx,
        runtime: runtime,
      )

      result["repo"].as_s.should eq("github.com/lefinepro/ocawe")
      result["repo_url"].as_s.should eq("git@github.com:lefinepro/ocawe.git")
      result["transport"].as_s.should eq("git+ssh")
      result["local_path"].as_s.ends_with?("github.com/lefinepro/ocawe/caws/10-acp-agent").should eq(true)
      result["workflow_id"].as_s.should eq("10-acp-agent")
      result["cawfile"].as_s.ends_with?("Cawfile").should eq(true)
      File.read(clone_url_file).strip.should eq("git@github.com:lefinepro/ocawe.git")
    ensure
      if old_path
        ENV["PATH"] = old_path
      else
        ENV.delete("PATH")
      end
      if old_cache
        ENV["OCAWE_CACHE_DIR"] = old_cache
      else
        ENV.delete("OCAWE_CACHE_DIR")
      end
      FileUtils.rm_rf(tmp_dir)
    end
  end
end
