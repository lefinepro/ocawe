require "./spec_helper"

describe "ACD::Kemal::App federation ticket routing" do
  it "extracts workflow id from actor URL" do
    app = ACD::Kemal::App.new(0)

    app.test_workflow_id_from_actor("http://127.0.0.1:4111/actors/prepare-order").should eq("prepare-order")
    app.test_workflow_id_from_actor("https://example.com/workflow/actors/triage/").should eq("triage")
  end

  it "falls back to the only loaded workflow for non-standard actor URLs" do
    app = ACD::Kemal::App.new(0)
    app.test_set_workflow_ids(["solver"])

    app.test_workflow_id_from_actor("https://oq.col.pub/order-queue").should eq("solver")
  end

  it "resolves workflow actor from string or hash node" do
    app = ACD::Kemal::App.new(0)

    app.test_federation_actor_from_node(JSON.parse("\"http://127.0.0.1:4111/actors/prepare-order\"")).should eq(
      "http://127.0.0.1:4111/actors/prepare-order"
    )
    app.test_federation_actor_from_node(JSON.parse(%({"id":"http://127.0.0.1:4111/actors/prepare-order"}))).should eq(
      "http://127.0.0.1:4111/actors/prepare-order"
    )
  end

  it "resolves workflow actor from ticket assignee or attributedTo and from body workflow_id" do
    app = ACD::Kemal::App.new(0)
    local_domain = "http://127.0.0.1:4111"
    body = {
      "@context"    => json_str(Aptok::ACTIVITYSTREAMS_CONTEXT),
      "type"        => json_str("Create"),
      "workflow_id" => json_str("prepare-order"),
    } of String => JSON::Any

    ticket_with_assignee = {
      "type"     => json_str("Ticket"),
      "assignee" => JSON.parse(%({"id":"http://127.0.0.1:4111/actors/triage"})),
    } of String => JSON::Any
    app.test_resolve_ticket_workflow_actor(body, ticket_with_assignee, local_domain).should eq("http://127.0.0.1:4111/actors/triage")

    ticket_with_attributed_to = {
      "type"         => json_str("Ticket"),
      "attributedTo" => json_str("http://127.0.0.1:4111/actors/prepare-order"),
    } of String => JSON::Any
    app.test_resolve_ticket_workflow_actor(body, ticket_with_attributed_to, local_domain).should eq("http://127.0.0.1:4111/actors/prepare-order")

    ticket_without_owner = {
      "type" => json_str("Ticket"),
    } of String => JSON::Any
    app.test_resolve_ticket_workflow_actor(body, ticket_without_owner, local_domain).should eq("http://127.0.0.1:4111/actors/prepare-order")
  end

  it "falls back to the subscribed local actor when ticket routing fields are absent" do
    app = ACD::Kemal::App.new(0)
    local_domain = "http://127.0.0.1:4111"
    body = {
      "@context" => json_str(Aptok::ACTIVITYSTREAMS_CONTEXT),
      "type"     => json_str("Ticket"),
    } of String => JSON::Any
    ticket = {
      "type" => json_str("Ticket"),
    } of String => JSON::Any

    app.test_resolve_ticket_workflow_actor(
      body,
      ticket,
      local_domain,
      "http://127.0.0.1:4111/actors/deploy-on-akash"
    ).should eq("http://127.0.0.1:4111/actors/deploy-on-akash")
  end
end
