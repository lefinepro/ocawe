require "./spec_helper"

describe "ACD::Kemal::App federation actor document" do
  it "resolves internal federation handles through the peer model" do
    peers = Ocawe::Federation::InternalDomain.parse_peers([
      "fmatch=http://127.0.0.1:7277",
    ])
    Ocawe::Federation::InternalDomain.resolve_actor("@fmatch@fedi.internal", peers).should eq(
      "http://127.0.0.1:7277/actors/fmatch"
    )
    Ocawe::Federation::InternalDomain.resolve_actor("@unknown@example.com", peers).should be_nil
  end

  it "builds an actor document for a loaded workflow" do
    key_path = File.tempname("ocawe-fed-key", ".pem")
    Process.run("openssl", args: ["genrsa", "-out", key_path, "2048"], output: Process::Redirect::Close, error: Process::Redirect::Close).success?.should be_true

    settings = Ocawe::Config::Settings.new(
      workflows: Ocawe::Config::WorkflowSettings.new(
        preferred_workflows_root: "./src/workflows"
      ),
      federation: Ocawe::Config::FederationSettings.new(
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
    actor["inbox"]?.try(&.as_s?).should eq("https://deployer.col.pub/actors/deploy-on-akash/inbox")
    actor["outbox"]?.try(&.as_s?).should eq("https://deployer.col.pub/actors/deploy-on-akash/outbox")
    actor["publicKey"]?.try(&.as_h?).not_nil!["id"]?.try(&.as_s?).should eq(
      "https://deployer.col.pub/actors/deploy-on-akash#main-key"
    )
  ensure
    if path = key_path
      File.delete(path) if File.exists?(path)
    end
  end

  it "renders a configured Service actor without changing the default" do
    key_path = File.tempname("ocawe-service-key", ".pem")
    Process.run("openssl", args: ["genrsa", "-out", key_path, "2048"], output: Process::Redirect::Close, error: Process::Redirect::Close).success?.should be_true
    settings = Ocawe::Config::Settings.new(
      workflows: Ocawe::Config::WorkflowSettings.new(preferred_workflows_root: "./src/workflows"),
      federation: Ocawe::Config::FederationSettings.new(
        local_actor: "https://rotator.example/actors/rotator",
        local_key_id: "https://rotator.example/actors/rotator#main-key",
        local_private_key_path: key_path,
        actor_type: "Service"
      )
    )
    app = ACD::Kemal::App.new(0, settings: settings)
    app.test_set_workflow_ids(["rotator"])
    actor = app.test_local_actor_document("rotator")
    actor["type"]?.try(&.as_s?).should eq("Service")
    actor["id"]?.try(&.as_s?).should eq("https://rotator.example/actors/rotator")
    actor["inbox"]?.try(&.as_s?).should eq("https://rotator.example/actors/rotator/inbox")
    actor["outbox"]?.try(&.as_s?).should eq("https://rotator.example/actors/rotator/outbox")
    actor["publicKey"]?.try(&.as_h?).should_not be_nil
  ensure
    if path = key_path
      File.delete(path) if File.exists?(path)
    end
  end

  it "rejects an invalid actor type" do
    expect_raises(ArgumentError, /actor_type/) do
      Ocawe::Config::FederationSettings.new(actor_type: "Bot")
    end
  end
end
