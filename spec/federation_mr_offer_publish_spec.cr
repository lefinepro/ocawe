require "./spec_helper"

describe "ACD::Kemal::App federation merge request format" do
  it "publishes exchange-compatible Update(Ticket) results for exchange actors" do
    app = ACD::Kemal::App.new(0)
    ticket = JSON.parse(%({
      "type": "Ticket",
      "id": "https://exchange.example/orders/117",
      "name": "Cogni solver e2e",
      "summary": "Cogni solver e2e",
      "content": "Calculate 50+50 and return only the number",
      "inReplyTo": "370c7284-0f2b-464b-ae59-3a7cbf6d6c0e",
      "attachment": [
        {"type": "PropertyValue", "name": "externalId", "value": "370c7284-0f2b-464b-ae59-3a7cbf6d6c0e"},
        {"type": "PropertyValue", "name": "orderId", "value": "117"}
      ]
    })).as_h
    output = {
      "status"  => json_str("success"),
      "content" => json_str("100"),
    } of String => JSON::Any

    app.test_publish_result_activity_from_output(
      workflow_id: "agent-codex-workflow",
      run_id: "run-exchange-1",
      run_status: "success",
      output: output,
      ticket: ticket,
      requested_activity: "ticket",
      remote_actor: "https://exchange.example/actor/code",
      local_actor: "http://solver.example/actor/agent-codex-workflow",
      workflow_actor: "https://lefine.pro/actor/staff",
      local_domain: "http://solver.example",
      published_at: "2026-03-07T00:00:00Z",
    )

    events = app.test_list_outbox_events
    events.size.should eq(1)
    activity = events.first["activity"]?.try(&.as_h?)
    activity.should_not be_nil
    activity.not_nil!["type"]?.try(&.as_s?).should eq("Update")
    activity.not_nil!["actor"]?.try(&.as_s?).should eq("http://solver.example/actor/agent-codex-workflow")
    activity.not_nil!["target"]?.try(&.as_s?).should eq("370c7284-0f2b-464b-ae59-3a7cbf6d6c0e")
    activity.not_nil!["orderId"]?.try(&.as_s?).should eq("117")

    result_ticket = activity.not_nil!["object"]?.try(&.as_h?)
    result_ticket.should_not be_nil
    result_ticket.not_nil!["type"]?.try(&.as_s?).should eq("Ticket")
    result_ticket.not_nil!["id"]?.try(&.as_s?).should eq("370c7284-0f2b-464b-ae59-3a7cbf6d6c0e")
    result_ticket.not_nil!["status"]?.try(&.as_s?).should eq("completed")
    result_ticket.not_nil!["content"]?.try(&.as_s?).should eq("100")

    attachments = result_ticket.not_nil!["attachment"]?.try(&.as_a?)
    attachments.should_not be_nil
    attachment_names = attachments.not_nil!.compact_map do |entry|
      record = entry.as_h?
      next nil unless record
      record["name"]?.try(&.as_s?)
    end
    attachment_names.should contain("status")
    attachment_names.should contain("orderId")
    attachment_names.should contain("externalId")
  end

  it "publishes merge result as Offer(Ticket) with Patch when requested activity is merge" do
    app = ACD::Kemal::App.new(0)
    ticket = JSON.parse(%({
      "type": "Ticket",
      "summary": "Install fail2ban",
      "source": {
        "mediaType": "text/markdown; variant=Commonmark",
        "content": "Please install fail2ban via playbook"
      }
    })).as_h
    output = {
      "status" => json_str("ok"),
      "agent_output" => json_str(%({
        "type": "Offer",
        "object": {
          "type": "Ticket",
          "summary": "Install fail2ban",
          "source": {
            "mediaType": "text/markdown; variant=Commonmark",
            "content": "Please install fail2ban via playbook"
          },
          "content": "<p>Please install fail2ban via playbook</p>",
          "mediaType": "text/html",
          "attachment": {
            "type": "Offer",
            "object": {
              "type": "OrderedCollection",
              "totalItems": 1,
              "items": [
                {
                  "type": "Patch",
                  "mediaType": "application/x-git-patch",
                  "content": "diff --git a/playbook.toml b/playbook.toml\\nnew file mode 100644\\n--- /dev/null\\n+++ b/playbook.toml\\n@@ -0,0 +1,1 @@\\n+name = \\\"install-fail2ban\\\""
                }
              ]
            }
          }
        }
      })),
    } of String => JSON::Any

    app.test_publish_result_activity_from_output(
      workflow_id: "solver",
      run_id: "run-1",
      run_status: "ok",
      output: output,
      ticket: ticket,
      requested_activity: "merge",
      remote_actor: "https://remote.example/actors/bot",
      workflow_actor: "https://local.example/actors/solver",
      local_domain: "https://local.example",
      published_at: "2026-03-07T00:00:00Z",
    )

    events = app.test_list_outbox_events
    events.size.should eq(1)
    activity = events.first["activity"]?.try(&.as_h?)
    activity.should_not be_nil
    activity.not_nil!["type"]?.try(&.as_s?).should eq("Offer")

    mr_ticket = activity.not_nil!["object"]?.try(&.as_h?)
    mr_ticket.should_not be_nil
    mr_ticket.not_nil!["type"]?.try(&.as_s?).should eq("Ticket")
    mr_ticket.not_nil!.has_key?("id").should be_false

    attachment = mr_ticket.not_nil!["attachment"]?.try(&.as_h?)
    attachment.should_not be_nil
    attachment.not_nil!["type"]?.try(&.as_s?).should eq("Offer")

    patch_collection = attachment.not_nil!["object"]?.try(&.as_h?)
    patch_collection.should_not be_nil
    patches = patch_collection.not_nil!["orderedItems"]?.try(&.as_a?) || patch_collection.not_nil!["items"]?.try(&.as_a?)
    patches.should_not be_nil
    patches.not_nil!.size.should eq(1)
    patch = patches.not_nil!.first.as_h
    patch["type"]?.try(&.as_s?).should eq("Patch")
  end

  it "strips non-ForgeFed fields from merge Offer payload before publishing" do
    app = ACD::Kemal::App.new(0)
    ticket = JSON.parse(%({
      "type": "Ticket",
      "summary": "Install fail2ban",
      "source": {
        "mediaType": "text/markdown; variant=Commonmark",
        "content": "Please install fail2ban via playbook"
      }
    })).as_h
    output = {
      "status" => json_str("ok"),
      "agent_output" => json_str(%({
        "type": "Offer",
        "input": {"repo_path":"cogni/scripts/playbook.toml"},
        "task": "update-playbook",
        "metadata": {"tool":"mock"},
        "object": {
          "type": "Ticket",
          "id": "https://remote.example/tickets/123",
          "summary": "Install fail2ban",
          "source": {
            "mediaType": "text/markdown; variant=Commonmark",
            "content": "Please install fail2ban via playbook"
          },
          "content": "<p>Please install fail2ban via playbook</p>",
          "mediaType": "text/html",
          "ticket": "123",
          "attachment": {
            "type": "Offer",
            "origin": "https://repo.example/feature",
            "target": "https://repo.example/main",
            "metadata": {"debug":"yes"},
            "object": {
              "type": "OrderedCollection",
              "totalItems": 1,
              "repo_path": "cogni/scripts/playbook.toml",
              "items": [
                {
                  "type": "Patch",
                  "mediaType": "application/x-git-patch",
                  "content": "diff --git a/playbook.toml b/playbook.toml\\n+name = \\\"install-fail2ban\\\"",
                  "path": "playbook.toml",
                  "sha": "abc123"
                }
              ]
            }
          }
        }
      })),
    } of String => JSON::Any

    app.test_publish_result_activity_from_output(
      workflow_id: "solver",
      run_id: "run-strip-1",
      run_status: "ok",
      output: output,
      ticket: ticket,
      requested_activity: "merge",
      remote_actor: "https://remote.example/actors/bot",
      workflow_actor: "https://local.example/actors/solver",
      local_domain: "https://local.example",
      published_at: "2026-03-07T00:00:00Z",
    )

    events = app.test_list_outbox_events
    events.size.should eq(1)
    activity = events.first["activity"]?.try(&.as_h?)
    activity.should_not be_nil

    activity.not_nil!.has_key?("input").should be_false
    activity.not_nil!.has_key?("task").should be_false
    activity.not_nil!.has_key?("metadata").should be_false

    mr_ticket = activity.not_nil!["object"]?.try(&.as_h?)
    mr_ticket.should_not be_nil
    mr_ticket.not_nil!.has_key?("id").should be_false
    mr_ticket.not_nil!.has_key?("ticket").should be_false

    attachment = mr_ticket.not_nil!["attachment"]?.try(&.as_h?)
    attachment.should_not be_nil
    attachment.not_nil!.has_key?("metadata").should be_false

    patch_collection = attachment.not_nil!["object"]?.try(&.as_h?)
    patch_collection.should_not be_nil
    patch_collection.not_nil!.has_key?("repo_path").should be_false

    patches = patch_collection.not_nil!["orderedItems"]?.try(&.as_a?) || patch_collection.not_nil!["items"]?.try(&.as_a?)
    patches.should_not be_nil
    patches.not_nil!.size.should eq(1)
    patch = patches.not_nil!.first.as_h
    patch.has_key?("path").should be_false
    patch.has_key?("sha").should be_false
  end

  it "fails fast for merge output that is not ForgeFed Offer JSON" do
    app = ACD::Kemal::App.new(0)
    ticket = JSON.parse(%({
      "type": "Ticket",
      "summary": "Update config",
      "source": {
        "mediaType": "text/markdown; variant=Commonmark",
        "content": "Please update config"
      }
    })).as_h
    output = {
      "status"  => json_str("ok"),
      "content" => json_str(%({
        "status": "success",
        "result": "Applied config changes",
        "patch": "diff --git a/app.conf b/app.conf\\n+enabled=true"
      })),
    } of String => JSON::Any

    app.test_publish_result_activity_from_output(
      workflow_id: "solver",
      run_id: "run-2",
      run_status: "ok",
      output: output,
      ticket: ticket,
      requested_activity: "merge",
      remote_actor: "https://remote.example/actors/bot",
      workflow_actor: "https://local.example/actors/solver",
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
    note.not_nil!["content"]?.try(&.as_s?).to_s.includes?("merge output rejected").should eq(true)
  end
end
