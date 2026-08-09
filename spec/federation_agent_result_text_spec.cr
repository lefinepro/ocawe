require "./spec_helper"

# Regression cover for the result text a plain agent workflow publishes back to
# the requesting actor. A ticket routed into a workflow is copied into the run
# input, so the run output keeps the inbound text under `content` while the
# agent's own answer lands in `last_response`. Preferring `content` made the
# receiver echo the request instead of replying, which broke the documented
# Create(Ticket) -> Create(Note) round trip exercised by
# `spec/e2e/activitypub_agent_communication_spec.cr`.
describe "ACD::Kemal::App federation agent result text" do
  it "publishes the agent answer from last_response instead of echoing the inbound ticket text" do
    app = ACD::Kemal::App.new(0)
    ticket = JSON.parse(%({
      "type": "Ticket",
      "id": "https://remote.example/tickets/42",
      "name": "Draft a reply",
      "summary": "Draft a reply"
    })).as_h
    output = {
      "last_response" => json_str("[mock chat_completion] agent answer"),
      # What the router copied into the run input, echoed back by the node.
      "content" => json_str("Draft a reply"),
    } of String => JSON::Any

    app.test_publish_result_activity_from_output(
      workflow_id: "responder",
      run_id: "run-last-response",
      run_status: "success",
      output: output,
      ticket: ticket,
      requested_activity: "",
      remote_actor: "https://remote.example/actors/sender",
      workflow_actor: "https://local.example/actors/responder",
      local_domain: "https://local.example",
      published_at: "2026-03-07T00:00:00Z",
    )

    events = app.test_list_outbox_events
    events.size.should eq(1)
    activity = events.first["activity"]?.try(&.as_h?)
    activity.should_not be_nil
    activity.not_nil!["type"]?.try(&.as_s?).should eq("Create")

    note = activity.not_nil!["object"]?.try(&.as_h?)
    note.should_not be_nil
    note.not_nil!["type"]?.try(&.as_s?).should eq("Note")
    note.not_nil!["inReplyTo"]?.try(&.as_s?).should eq("https://remote.example/tickets/42")
    note.not_nil!["content"]?.try(&.as_s?).should eq("[mock chat_completion] agent answer")
  end

  it "still falls back to content when the output has no agent answer" do
    app = ACD::Kemal::App.new(0)
    ticket = JSON.parse(%({
      "type": "Ticket",
      "id": "https://remote.example/tickets/43",
      "name": "Legacy node"
    })).as_h
    output = {
      "content" => json_str("legacy result text"),
    } of String => JSON::Any

    app.test_publish_result_activity_from_output(
      workflow_id: "responder",
      run_id: "run-content-fallback",
      run_status: "success",
      output: output,
      ticket: ticket,
      requested_activity: "",
      remote_actor: "https://remote.example/actors/sender",
      workflow_actor: "https://local.example/actors/responder",
      local_domain: "https://local.example",
      published_at: "2026-03-07T00:00:00Z",
    )

    events = app.test_list_outbox_events
    events.size.should eq(1)
    note = events.first["activity"]?.try(&.as_h?).try(&.["object"]?).try(&.as_h?)
    note.should_not be_nil
    note.not_nil!["content"]?.try(&.as_s?).should eq("legacy result text")
  end

  it "keeps explicit federation_result_text ahead of the agent answer" do
    app = ACD::Kemal::App.new(0)
    ticket = JSON.parse(%({
      "type": "Ticket",
      "id": "https://remote.example/tickets/44",
      "name": "Explicit text"
    })).as_h
    output = {
      "federation_result_text" => json_str("explicit federation text"),
      "last_response"          => json_str("[mock chat_completion] agent answer"),
      "content"                => json_str("Explicit text"),
    } of String => JSON::Any

    app.test_publish_result_activity_from_output(
      workflow_id: "responder",
      run_id: "run-explicit-text",
      run_status: "success",
      output: output,
      ticket: ticket,
      requested_activity: "",
      remote_actor: "https://remote.example/actors/sender",
      workflow_actor: "https://local.example/actors/responder",
      local_domain: "https://local.example",
      published_at: "2026-03-07T00:00:00Z",
    )

    events = app.test_list_outbox_events
    events.size.should eq(1)
    note = events.first["activity"]?.try(&.as_h?).try(&.["object"]?).try(&.as_h?)
    note.should_not be_nil
    note.not_nil!["content"]?.try(&.as_s?).should eq("explicit federation text")
  end
end
