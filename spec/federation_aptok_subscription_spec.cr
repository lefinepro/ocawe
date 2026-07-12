require "./spec_helper"

describe "ACD::Kemal::App Aptok federation subscriptions" do
  it "builds a pending Aptok-backed follow record from a domain handle without discovered inbox" do
    settings = Ocawe::Config::Settings.new(
      workflows: Ocawe::Config::WorkflowSettings.new(preferred_workflows_root: "./src/workflows"),
      federation: Ocawe::Config::FederationSettings.new(local_actor: "https://local.example/actors/planner")
    )
    app = ACD::Kemal::App.new(0, settings: settings)

    record = app.test_ensure_aptok_subscription("@oq.col.pub")

    record["local_actor"].as_s.should eq("https://local.example/actors/planner")
    record["remote_actor"].as_s.should eq("https://oq.col.pub/actors/order-queue")
    record["remote_inbox"].as_s.should eq("")
    record["queue"].as_s.should eq("order-queue")
    record["status"].as_s.should eq("pending")
  end
end
