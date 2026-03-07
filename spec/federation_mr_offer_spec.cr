require "./spec_helper"

describe "ACD::Kemal::App federation merge request format" do
  it "accepts Offer(Ticket) and infers merge workflow activity" do
    app = ACD::Kemal::App.new(0)
    activity = JSON.parse(%({
      "type": "Offer",
      "object": {
        "type": "Ticket",
        "summary": "Fix animation",
        "attachment": {
          "type": "Offer",
          "origin": "https://forge.example/repo/source",
          "target": "https://forge.example/repo/main"
        }
      }
    })).as_h

    payload = app.test_extract_ticket_activity_payload(activity)
    payload.should_not be_nil
    payload.not_nil![:activity_type].should eq("Offer")
    payload.not_nil![:ticket]["type"]?.try(&.as_s?).should eq("Ticket")
    app.test_infer_ticket_workflow_activity(activity, payload.not_nil![:ticket], "Offer").should eq("merge")
  end

  it "builds MR Offer in ForgeFed Open shape from a ticket" do
    app = ACD::Kemal::App.new(0)
    ticket = JSON.parse(%({
      "type": "Ticket",
      "summary": "Fix animation <bug>",
      "target": "https://patch.example/tracker",
      "source": {
        "mediaType": "text/markdown; variant=Commonmark",
        "content": "Please review this MR"
      },
      "attachment": {
        "type": "Offer",
        "origin": "https://repo.example/feature",
        "target": "https://repo.example/main"
      }
    })).as_h
    output = {
      "mr_summary"       => json_str("Fix animation <bug>"),
      "mr_patch_tracker" => json_str("https://patch.example/tracker"),
      "mr_origin"        => json_str("https://repo.example/feature"),
      "mr_target"        => json_str("https://repo.example/main"),
      "mr_patches"       => json_any(["diff --git a/app.cr b/app.cr\n+puts :ok"]),
    } of String => JSON::Any

    activity = app.test_build_merge_result_offer_activity(
      suffix: "abc123",
      ticket: ticket,
      output: output,
      remote_actor: "https://remote.example/actors/bot",
      workflow_actor: "https://local.example/actors/solver",
      local_domain: "https://local.example",
      result_text: "Patch set prepared",
    )

    activity["type"]?.try(&.as_s?).should eq("Offer")
    activity["target"]?.try(&.as_s?).should eq("https://patch.example/tracker")

    mr_ticket = activity["object"]?.try(&.as_h?)
    mr_ticket.should_not be_nil
    mr_ticket.not_nil!["type"]?.try(&.as_s?).should eq("Ticket")
    mr_ticket.not_nil!.has_key?("id").should be_false
    mr_ticket.not_nil!["attributedTo"]?.try(&.as_s?).should eq("https://local.example/actors/solver")
    mr_ticket.not_nil!["summary"]?.try(&.as_s?).should eq("Fix animation &lt;bug&gt;")
    mr_ticket.not_nil!["mediaType"]?.try(&.as_s?).should eq("text/html")

    source = mr_ticket.not_nil!["source"]?.try(&.as_h?)
    source.should_not be_nil
    source.not_nil!["mediaType"]?.try(&.as_s?).should eq("text/markdown; variant=Commonmark")
    source.not_nil!["content"]?.try(&.as_s?).should eq("Please review this MR")

    attachment = mr_ticket.not_nil!["attachment"]?.try(&.as_h?)
    attachment.should_not be_nil
    attachment.not_nil!["type"]?.try(&.as_s?).should eq("Offer")
    attachment.not_nil!["origin"]?.try(&.as_s?).should eq("https://repo.example/feature")
    attachment.not_nil!["target"]?.try(&.as_s?).should eq("https://repo.example/main")

    patch_collection = attachment.not_nil!["object"]?.try(&.as_h?)
    patches = patch_collection.try(&.["orderedItems"]?).try(&.as_a?)
    patches.should_not be_nil
    patches.not_nil!.size.should eq(1)
    first_patch = patches.not_nil!.first.as_h
    first_patch["attributedTo"]?.try(&.as_s?).should eq("https://local.example/actors/solver")
    first_patch["mediaType"]?.try(&.as_s?).should eq("application/x-git-patch")
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
        "status": "success",
        "mr_diff": "diff --git a/playbook.toml b/playbook.toml\\nnew file mode 100644\\n--- /dev/null\\n+++ b/playbook.toml\\n@@ -0,0 +1,1 @@\\n+name = \\\"install-fail2ban\\\""
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
    patches = patch_collection.not_nil!["orderedItems"]?.try(&.as_a?)
    patches.should_not be_nil
    patches.not_nil!.size.should eq(1)
    patch = patches.not_nil!.first.as_h
    patch["type"]?.try(&.as_s?).should eq("Patch")
  end
end
