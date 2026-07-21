require "./spec_helper"

describe "ACD::Kemal::App federation actor document" do
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

  it "publishes Cawfile federation resource metadata on the actor document" do
    settings = Ocawe::Config::Settings.new(
      workflows: Ocawe::Config::WorkflowSettings.new(preferred_workflows_root: "./src/workflows"),
      federation: Ocawe::Config::FederationSettings.new(
        local_actor: "https://proxy.example/actors/proxy"
      )
    )
    app = ACD::Kemal::App.new(0, settings: settings)
    app.test_set_workflow_ids(["proxy"])
    app.test_set_workflow_federation_resource(
      "proxy",
      id: "proxy",
      name: "Proxy links",
      description: "Generates active proxy links",
      tags: ["proxy", "xray", "mtproto"]
    )

    actor = app.test_local_actor_document("proxy")
    capability = actor["attachment"]?.try(&.as_a?).not_nil!.first.as_h

    capability["id"]?.try(&.as_s?).should eq("proxy")
    capability["resourceConformsTo"]?.try(&.as_s?).should eq("https://proxy.example/resources/proxy")
    capability["summary"]?.try(&.as_s?).should eq("Generates active proxy links")
    capability["action"]?.try(&.as_s?).should eq("deliverService")
    capability["purpose"]?.try(&.as_s?).should eq("request")
    actor["tag"]?.try(&.as_a?).not_nil!.map { |tag| tag.as_h["name"]?.try(&.as_s?) }.should eq(["#proxy", "#xray", "#mtproto"])
  end

  it "keeps deployment capability overrides compatible with Cawfile resources" do
    previous_resource = ENV["OCAWE_FEDERATION_RESOURCE_CONFORMS_TO"]?
    previous_action = ENV["OCAWE_FEDERATION_ACTION"]?
    previous_purpose = ENV["OCAWE_FEDERATION_PURPOSE"]?
    ENV["OCAWE_FEDERATION_RESOURCE_CONFORMS_TO"] = "https://fmatch/marketplace/resources/model"
    ENV["OCAWE_FEDERATION_ACTION"] = "deliverService"
    ENV["OCAWE_FEDERATION_PURPOSE"] = "request"

    settings = Ocawe::Config::Settings.new(
      workflows: Ocawe::Config::WorkflowSettings.new(preferred_workflows_root: "./src/workflows"),
      federation: Ocawe::Config::FederationSettings.new(
        local_actor: "http://rotator:8080/actors/rotator"
      )
    )
    app = ACD::Kemal::App.new(0, settings: settings)
    app.test_set_workflow_ids(["rotator"])
    app.test_set_workflow_federation_resource(
      "rotator",
      id: "rotator",
      action: "fallbackAction",
      purpose: "fallbackPurpose"
    )

    capability = app.test_local_actor_document("rotator")["attachment"]?.try(&.as_a?).not_nil!.first.as_h
    capability["resourceConformsTo"]?.try(&.as_s?).should eq("https://fmatch/marketplace/resources/model")
    capability["action"]?.try(&.as_s?).should eq("deliverService")
    capability["purpose"]?.try(&.as_s?).should eq("request")
  ensure
    if value = previous_resource
      ENV["OCAWE_FEDERATION_RESOURCE_CONFORMS_TO"] = value
    else
      ENV.delete("OCAWE_FEDERATION_RESOURCE_CONFORMS_TO")
    end
    if value = previous_action
      ENV["OCAWE_FEDERATION_ACTION"] = value
    else
      ENV.delete("OCAWE_FEDERATION_ACTION")
    end
    if value = previous_purpose
      ENV["OCAWE_FEDERATION_PURPOSE"] = value
    else
      ENV.delete("OCAWE_FEDERATION_PURPOSE")
    end
  end
end
