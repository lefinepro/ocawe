require "./spec_helper"

describe "ACD::Kemal::App federation outbox transport parsing" do
  it "extracts task activities from orderedItems and items variants" do
    app = ACD::Kemal::App.new(0)
    activity_a = JSON.parse(%({"id":"https://remote.example/outbox/a","type":"Offer","object":{"type":"Ticket","summary":"PRD-A"}}))
    activity_b = JSON.parse(%({"id":"https://remote.example/outbox/b","type":"Offer","object":{"type":"Ticket","summary":"PRD-B"}}))

    ordered_doc = {
      "type"         => json_str("OrderedCollection"),
      "orderedItems" => json_any([activity_a]),
    } of String => JSON::Any
    items_doc = {
      "type"  => json_str("OrderedCollection"),
      "items" => json_any([activity_b]),
    } of String => JSON::Any

    ordered = app.test_extract_activities_from_outbox(ordered_doc)
    ordered.size.should eq(1)
    ordered.first["id"]?.try(&.as_s?).should eq("https://remote.example/outbox/a")

    items = app.test_extract_activities_from_outbox(items_doc)
    items.size.should eq(1)
    items.first["id"]?.try(&.as_s?).should eq("https://remote.example/outbox/b")
  end
end
