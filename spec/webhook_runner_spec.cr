require "./spec_helper"
require "file_utils"

describe "Ocawe webhook runner" do
  it "loads webhook settings from Cawfile" do
    tmp_dir = "/tmp/ocawe_webhook_settings_#{Random.rand(1_000_000)}"
    Dir.mkdir_p(tmp_dir)
    begin
      File.write(File.join(tmp_dir, "Cawfile"), <<-CAW)
settings do
  webhooks = true
  webhooks.secret_env = "CUSTOM_WEBHOOK_SECRET"
  webhooks.workspace_root = "/tmp/ocawe-runner"
  webhooks.default_workflow = "deploy"
  webhooks.allowed_repos = ["source.lefine.pro/lefinepro/*"]
  webhooks.allowed_refs = ["refs/heads/release"]
end

workflow "deploy" do
  exec "run.sh", runtime: {shell: "bash"}
end
CAW

      bundle = ACD::Discovery::CawfileLoader.load_root(tmp_dir)
      bundle.not_nil!.config_webhooks["enabled"].should eq(true)
      settings = OcaweCore::Utils::ConfigParser.apply_cawfile_settings(Ocawe::Config::Settings.default, bundle.not_nil!)

      settings.webhooks.enabled.should eq(true)
      settings.webhooks.secret_env.should eq("CUSTOM_WEBHOOK_SECRET")
      settings.webhooks.workspace_root.should eq("/tmp/ocawe-runner")
      settings.webhooks.default_workflow.should eq("deploy")
      settings.webhooks.allowed_repos.should eq(["source.lefine.pro/lefinepro/*"])
      settings.webhooks.allowed_refs.should eq(["refs/heads/release"])
    ensure
      FileUtils.rm_rf(tmp_dir)
    end
  end

  it "verifies GitHub and Gitea webhook signatures" do
    ENV["OCAWE_TEST_WEBHOOK_SECRET"] = "It's a Secret to Everybody"
    settings = Ocawe::Config::Settings.new(
      workflows: Ocawe::Config::WorkflowSettings.new("./src/workflows"),
      webhooks: Ocawe::Config::WebhookSettings.new(enabled: true, secret_env: "OCAWE_TEST_WEBHOOK_SECRET")
    )
    app = ACD::Kemal::App.new(0, settings: settings)
    payload = "Hello, World!"
    digest = "757107ea0eb2509fc211221cce984b8a37570b6d7586c22c46f4379c8b043e17"

    github_headers = HTTP::Headers{"X-Hub-Signature-256" => "sha256=#{digest}"}
    gitea_headers = HTTP::Headers{"X-Gitea-Signature" => digest}

    app.test_verify_webhook_signature(payload, github_headers).should be_true
    app.test_verify_webhook_signature(payload, gitea_headers).should be_true
    app.test_verify_webhook_signature(payload, HTTP::Headers{"X-Gitea-Signature" => "bad"}).should be_false
  ensure
    ENV.delete("OCAWE_TEST_WEBHOOK_SECRET")
  end

  it "checks out a webhook repository and starts the selected Cawfile workflow" do
    base_dir = "/tmp/ocawe_webhook_runner_#{Random.rand(1_000_000)}"
    repo_dir = File.join(base_dir, "repo")
    workspace_dir = File.join(base_dir, "workspaces")
    Dir.mkdir_p(repo_dir)

    begin
      File.write(File.join(repo_dir, "Cawfile"), <<-CAW)
settings do
  data.adapter = "memory"
end

struct Input
end

struct Output
end

@[Validate(Input, Output)]
workflow "deploy" do
  exec "run.sh", runtime: {shell: "bash"}
end
CAW
      File.write(File.join(repo_dir, "run.sh"), %(printf '{"ok":true,"source":"webhook"}\\n'\n))
      run_git(repo_dir, ["init"])
      run_git(repo_dir, ["add", "Cawfile", "run.sh"])
      run_git(repo_dir, ["-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "-m", "initial"])
      sha = git_output(repo_dir, ["rev-parse", "HEAD"])

      settings = Ocawe::Config::Settings.new(
        workflows: Ocawe::Config::WorkflowSettings.new("./src/workflows"),
        webhooks: Ocawe::Config::WebhookSettings.new(
          enabled: true,
          workspace_root: workspace_dir,
          default_workflow: "deploy",
          allowed_refs: ["refs/heads/release"]
        )
      )
      app = ACD::Kemal::App.new(0, settings: settings)
      body = JSON.parse({
        "ref"        => "refs/heads/release",
        "after"      => sha,
        "repository" => {
          "full_name" => "lefinepro/example",
          "clone_url" => repo_dir,
          "html_url"  => "https://source.lefine.pro/lefinepro/example",
        },
        "sender" => {"login" => "tester"},
      }.to_json).as_h

      response = app.test_handle_cawfile_webhook(
        body,
        HTTP::Headers{
          "X-Gitea-Event"    => "push",
          "X-Gitea-Delivery" => "delivery-1",
        }
      )

      response["status"].as_s.should eq("queued")
      response["workflow_id"].as_s.should eq("deploy")
      response["run_id"].as_s.should eq("webhook_delivery-1")
      response["status_url"].as_s.should eq("/v1/webhooks/runs/webhook_delivery-1")
      response["repository"].as_s.should eq("source.lefine.pro/lefinepro/example")
      File.exists?(File.join(workspace_dir, "source.lefine.pro", "lefinepro", "example", "Cawfile")).should be_true
    ensure
      FileUtils.rm_rf(base_dir)
    end
  end

  it "ignores pushes outside allowed refs" do
    settings = Ocawe::Config::Settings.new(
      workflows: Ocawe::Config::WorkflowSettings.new("./src/workflows"),
      webhooks: Ocawe::Config::WebhookSettings.new(
        enabled: true,
        allowed_refs: ["refs/heads/release"]
      )
    )
    app = ACD::Kemal::App.new(0, settings: settings)
    body = JSON.parse({
      "ref"        => "refs/heads/main",
      "after"      => "abc123",
      "repository" => {
        "full_name" => "lefinepro/example",
        "clone_url" => "/tmp/does-not-need-to-exist",
        "html_url"  => "https://source.lefine.pro/lefinepro/example",
      },
    }.to_json).as_h

    response = app.test_handle_cawfile_webhook(
      body,
      HTTP::Headers{
        "X-Gitea-Event"    => "push",
        "X-Gitea-Delivery" => "delivery-ignored",
      }
    )

    response["status"].as_s.should eq("ignored")
    response["reason"].as_s.should eq("ref not allowed")
  end
end

private def run_git(repo_dir : String, args : Array(String)) : Nil
  status = Process.run("git", args: args, chdir: repo_dir, output: Process::Redirect::Close, error: Process::Redirect::Inherit)
  status.success?.should be_true
end

private def git_output(repo_dir : String, args : Array(String)) : String
  io = IO::Memory.new
  status = Process.run("git", args: args, chdir: repo_dir, output: io, error: Process::Redirect::Inherit)
  status.success?.should be_true
  io.to_s.strip
end
