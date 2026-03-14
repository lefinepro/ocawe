require "./spec_helper"

describe Cogni::Federation::Subscriptions do
  it "parses subscription handles into actor urls" do
    target = Cogni::Federation::Subscriptions.parse_target("@oq.col.pub")
    target.remote_actor.should eq("https://oq.col.pub/actors/order-queue")
    target.queue.should eq("order-queue")

    actor_target = Cogni::Federation::Subscriptions.parse_target("@planner@oq.col.pub")
    actor_target.remote_actor.should eq("https://oq.col.pub/actors/planner")
    actor_target.queue.should eq("planner")
  end

  it "stores a resolved follow record from an actor document" do
    settings = Cogni::Config::Settings.new(
      workflows: Cogni::Config::WorkflowSettings.new(
        preferred_workflows_root: "./src/workflows",
      ),
      federation: Cogni::Config::FederationSettings.new(
        local_actor: "https://local.example/actors/planner",
      ),
    )
    store = Cogni::Federation::Store::Memory.new
    actor_document = JSON.parse(%(
      {
        "@context":"https://www.w3.org/ns/activitystreams",
        "id":"https://oq.col.pub/actors/order-queue",
        "type":"Application",
        "inbox":"https://oq.col.pub/federation/inbox",
        "outbox":"https://oq.col.pub/federation/outbox",
        "publicKey":{
          "id":"https://oq.col.pub/actors/order-queue#main-key",
          "publicKeyPem":"pem"
        }
      }
    )).as_h

    record = Cogni::Federation::Subscriptions.ensure(settings, store, "@oq.col.pub", actor_document: actor_document)

    record["status"].as_s.should eq("active")
    record["remote_actor"].as_s.should eq("https://oq.col.pub/actors/order-queue")
    record["remote_outbox"].as_s.should eq("https://oq.col.pub/federation/outbox")
    record["queue"].as_s.should eq("order-queue")
  end

  it "exposes forgefed_subscribe as a default node kind" do
    config_path = File.tempname("cogni-fed-subscribe", ".rcl")
    File.write(config_path, <<-RCL
      api = ["federation"]

      federation do
        adapter = "memory"
        local_actor = "https://local.example/actors/planner"
      end
    RCL
    )

    previous = ENV["COGNI_CONFIG_RCL"]?
    ENV["COGNI_CONFIG_RCL"] = config_path
    Cogni::RegistryApi.reset_all!

    workflow = Cogni::Workflow.create_workflow("wf-forgefed-subscribe")
    workflow
      .step(Cogni::NodeKind.new("forgefed_subscribe", {
        "name"           => json_str("@planner@oq.col.pub"),
        "actor_document" => JSON.parse(%(
          {
            "@context":"https://www.w3.org/ns/activitystreams",
            "id":"https://oq.col.pub/actors/planner",
            "type":"Application",
            "inbox":"https://oq.col.pub/federation/inbox",
            "outbox":"https://oq.col.pub/federation/outbox"
          }
        )),
      }), id: "forgefed_subscribe")
      .commit

    engine = Cogni::Workflow::Engine.new
    engine.register(workflow)

    result = engine.create_run("wf-forgefed-subscribe").start

    result.status.should eq("success")
    result.state.not_nil!["subscription_status"].as_s.should eq("active")
    result.state.not_nil!["remote_actor"].as_s.should eq("https://oq.col.pub/actors/planner")
    result.state.not_nil!["queue"].as_s.should eq("planner")
  ensure
    if previous
      ENV["COGNI_CONFIG_RCL"] = previous
    else
      ENV.delete("COGNI_CONFIG_RCL")
    end
    File.delete(config_path) if config_path && File.exists?(config_path)
  end
end
