require "./spec_helper"

describe "ACD::Kemal::App federation actor document" do
  it "builds an actor document for a loaded workflow" do
    key_path = File.tempname("cogni-fed-key", ".pem")
    Process.run("openssl", args: ["genrsa", "-out", key_path, "2048"], output: Process::Redirect::Close, error: Process::Redirect::Close).success?.should be_true

    settings = Cogni::Config::Settings.new(
      workflows: Cogni::Config::WorkflowSettings.new(
        preferred_workflows_root: "./src/workflows"
      ),
      federation: Cogni::Config::FederationSettings.new(
        local_actor: "https://deployer.col.pub/actors/deploy-on-akash",
        local_key_id: "https://deployer.col.pub/actors/deploy-on-akash#main-key",
        local_private_key_path: key_path
      )
    )
    app = ACD::Kemal::App.new(0, settings: settings)
    app.test_set_workflow_ids(["deploy-on-akash"])

    actor = app.test_local_actor_document("deploy-on-akash")

    actor["id"]?.try(&.as_s?).should eq("https://deployer.col.pub/actors/deploy-on-akash")
    actor["type"]?.try(&.as_s?).should eq("Application")
    actor["inbox"]?.try(&.as_s?).should eq("https://deployer.col.pub/federation/inbox")
    actor["outbox"]?.try(&.as_s?).should eq("https://deployer.col.pub/federation/outbox")
    actor["publicKey"]?.try(&.as_h?).not_nil!["id"]?.try(&.as_s?).should eq(
      "https://deployer.col.pub/actors/deploy-on-akash#main-key"
    )
  ensure
    if path = key_path
      File.delete(path) if File.exists?(path)
    end
  end
end
