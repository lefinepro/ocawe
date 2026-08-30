require "./spec_helper"

# Regression cover for the result text a plain agent workflow publishes back to
# the requesting actor. A ticket routed into a workflow is copied into the run
# input, so the run output keeps the inbound text under `content` while the
# agent's own answer lands in `last_response`. Preferring `content` made the
# receiver echo the request instead of replying, which broke the documented
# Create(Ticket) -> Offer(Ticket) round trip exercised by
# `spec/e2e/activitypub_agent_communication_spec.cr`.
describe "ACD::Kemal::App federation agent result text" do
  it "publishes the agent answer from last_response instead of echoing the inbound ticket text" do
    app = ACD::Kemal::App.new(0)
    ticket = JSON.parse(%({
      "type": "Ticket",
      "id": "https://remote.example/tickets/42",
      "taskRef": "orator-task-42",
      "executionId": "execution-42",
      "resultInbox": "https://router.example/inbox/actra",
      "name": "Draft a reply",
      "summary": "Draft a reply"
    })).as_h
    output = {
      "last_response" => json_str("[mock chat_completion] agent answer"),
      # What the router copied into the run input, echoed back by the node.
      "content" => json_str("Draft a reply"),
      "usage"   => JSON.parse(%({"prompt_tokens":20000,"completion_tokens":5000})),
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
    activity.not_nil!["type"]?.try(&.as_s?).should eq("Offer")

    result_ticket = activity.not_nil!["object"]?.try(&.as_h?)
    result_ticket.should_not be_nil
    result_ticket.not_nil!["type"]?.try(&.as_s?).should eq("Ticket")
    result_ticket.not_nil!["command"]?.try(&.as_s?).should eq("#result")
    result_ticket.not_nil!["inReplyTo"]?.try(&.as_s?).should eq("https://remote.example/tickets/42")
    result_ticket.not_nil!["content"]?.try(&.as_s?).should eq("[mock chat_completion] agent answer")
    result_ticket.not_nil!["taskRef"]?.try(&.as_s?).should eq("orator-task-42")
    result_ticket.not_nil!["executionId"]?.try(&.as_s?).should eq("execution-42")
    result_ticket.not_nil!["resultInbox"]?.try(&.as_s?).should eq("https://router.example/inbox/actra")
    result_ticket.not_nil!["usage"]?.try(&.["prompt_tokens"]?).try(&.as_i?).should eq(20_000)
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

  it "wraps explicit Note output in the correlated ForgeFed result Ticket" do
    app = ACD::Kemal::App.new(0)
    ticket = JSON.parse(%({
      "type":"Ticket",
      "id":"https://remote.example/tickets/45",
      "taskRef":"task-45",
      "executionId":"execution-45",
      "resultInbox":"https://router.example/inbox/actra"
    })).as_h
    output = {
      "federation_output" => JSON.parse(%({"type":"Create","object":{"type":"Note","content":"final model answer"}})),
      "content"           => json_str("final model answer"),
    } of String => JSON::Any

    app.test_publish_result_activity_from_output(
      workflow_id: "responder",
      run_id: "run-explicit-note",
      run_status: "completed",
      output: output,
      ticket: ticket,
      requested_activity: "",
      remote_actor: "https://remote.example/actors/sender",
      workflow_actor: "https://local.example/actors/responder",
      local_domain: "https://local.example",
      published_at: "2026-03-07T00:00:00Z",
    )

    activity = app.test_list_outbox_events.first["activity"]?.try(&.as_h?).not_nil!
    activity["type"]?.try(&.as_s?).should eq("Offer")
    result_ticket = activity["object"]?.try(&.as_h?).not_nil!
    result_ticket["type"]?.try(&.as_s?).should eq("Ticket")
    result_ticket["content"]?.try(&.as_s?).should eq("final model answer")
    result_ticket["executionId"]?.try(&.as_s?).should eq("execution-45")
  end
end
