require "./spec_helper"

describe "ACD::Kemal::App federation context type validation" do
  it "accepts ForgeFed Offer(Ticket) activity with nested ForgeFed objects" do
    app = ACD::Kemal::App.new(0)
    body = JSON.parse(%({
      "@context": ["https://www.w3.org/ns/activitystreams", "https://forgefed.org/ns"],
      "type": "Offer",
      "actor": "https://remote.example/actors/repo",
      "object": {
        "type": "Ticket",
        "id": "https://remote.example/tickets/1",
        "summary": "PRD-1",
        "origin": {"type": "Branch", "name": "feature"},
        "target": {"type": "Branch", "name": "main"},
        "attachment": {
          "type": "Offer",
          "object": {
            "type": "OrderedCollection",
            "items": [
              {"type": "Patch", "content": "diff --git a/a b/a\\n+1"}
            ]
          }
        }
      }
    })).as_h

    app.test_validate_contextual_federation_object(body, "activity").should be_nil
  end

  it "accepts exchange PropertyValue attachments under ActivityStreams attachment paths" do
    app = ACD::Kemal::App.new(0)
    body = JSON.parse(%({
      "@context": ["https://www.w3.org/ns/activitystreams", "https://forgefed.org/ns"],
      "type": "Offer",
      "actor": "https://exchange.example/actor/code",
      "object": {
        "type": "Ticket",
        "id": "https://exchange.example/orders/1",
        "summary": "Calculate 2+2",
        "attachment": [
          {"type": "PropertyValue", "name": "externalId", "value": "abc"},
          {"type": "PropertyValue", "name": "originServer", "value": "https://lefine.pro"},
          {"type": "PropertyValue", "name": "orderId", "value": "110"},
          {"type": "PropertyValue", "name": "workflow", "value": "VPN Deployment Workflow"}
        ]
      }
    })).as_h

    app.test_validate_contextual_federation_object(body, "activity").should be_nil
  end

  it "accepts exchange Status attachments under ActivityStreams attachment paths" do
    app = ACD::Kemal::App.new(0)
    body = JSON.parse(%({
      "@context": ["https://www.w3.org/ns/activitystreams", "https://forgefed.org/ns"],
      "type": "Update",
      "actor": "https://exchange.example/actor/code",
      "object": {
        "type": "Ticket",
        "id": "https://exchange.example/orders/1",
        "attachment": [
          {"type": "Status", "name": "Task Status", "value": "completed"}
        ]
      }
    })).as_h

    app.test_validate_contextual_federation_object(body, "activity").should be_nil
  end

  it "rejects unknown type under ActivityStreams context" do
    app = ACD::Kemal::App.new(0)
    body = JSON.parse(%({
      "@context": "https://www.w3.org/ns/activitystreams",
      "type": "BogusActivity",
      "actor": "https://remote.example/actors/alice",
      "object": {"type": "Note", "content": "hello"}
    })).as_h

    error = app.test_validate_contextual_federation_object(body, "activity")
    error.should_not be_nil
    error.not_nil!.should contain("$.type=BogusActivity is not allowed")
  end

  it "still rejects PropertyValue outside attachment compatibility paths" do
    app = ACD::Kemal::App.new(0)
    body = JSON.parse(%({
      "@context": "https://www.w3.org/ns/activitystreams",
      "type": "Create",
      "actor": "https://remote.example/actors/alice",
      "object": {"type": "PropertyValue", "name": "unexpected", "value": "hello"}
    })).as_h

    error = app.test_validate_contextual_federation_object(body, "activity")
    error.should_not be_nil
    error.not_nil!.should contain("$.object.type=PropertyValue is not allowed")
  end

  it "rejects actor-like object without inbox and outbox" do
    app = ACD::Kemal::App.new(0)
    body = JSON.parse(%({
      "@context": ["https://www.w3.org/ns/activitystreams", "https://forgefed.org/ns"],
      "type": "Repository",
      "id": "https://remote.example/repositories/core"
    })).as_h

    error = app.test_validate_contextual_federation_object(body, "actor")
    error.should_not be_nil
    error.not_nil!.should contain("$.inbox is required for actor type Repository")
    error.not_nil!.should contain("$.outbox is required for actor type Repository")
  end

  it "rejects outbox payload that is not a collection" do
    app = ACD::Kemal::App.new(0)
    body = JSON.parse(%({
      "@context": "https://www.w3.org/ns/activitystreams",
      "type": "Note",
      "content": "not a collection"
    })).as_h

    error = app.test_validate_contextual_federation_object(body, "collection")
    error.should_not be_nil
    error.not_nil!.should contain("$.type must be a Collection or OrderedCollection")
  end
end
