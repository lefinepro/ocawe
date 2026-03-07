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
      "status" => json_str("ok"),
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

  it "matches ForgeFed Offer(Ticket) shape with branch origin/target and items list" do
    app = ACD::Kemal::App.new(0)
    ticket = JSON.parse(%({
      "type": "Ticket",
      "summary": "Fix the animation bug",
      "content": "<p>Please review, thanks!</p>",
      "target": "https://dev.example/projects/game-of-life/pr-tracker",
      "source": {
        "mediaType": "text/markdown; variant=Commonmark",
        "content": "Please review, thanks!"
      },
      "attachment": {
        "type": "Offer",
        "origin": {
          "type": "Branch",
          "context": "https://forge.example/luke/game-of-life",
          "ref": "refs/heads/fix-animation-bug"
        },
        "target": {
          "type": "Branch",
          "context": "https://dev.example/projects/game-of-life/repo",
          "ref": "refs/heads/main"
        }
      }
    })).as_h

    output = {
      "mr_summary"       => json_str("Fix the animation bug"),
      "mr_patch_tracker" => json_str("https://dev.example/projects/game-of-life/pr-tracker"),
      "mr_patches"       => json_any(["From c9ae5f4ff4a330b6e1196ceb7db1665bd4c1..."]),
    } of String => JSON::Any

    activity = app.test_build_merge_result_offer_activity(
      suffix: "uCSW6urN",
      ticket: ticket,
      output: output,
      remote_actor: "https://dev.example/actors/bot",
      workflow_actor: "https://forge.example/luke",
      local_domain: "https://forge.example",
      result_text: "Please review, thanks!",
    )

    context = activity["@context"]?.try(&.as_a?)
    context.should_not be_nil
    context.not_nil!.map(&.as_s).should eq([
      "https://www.w3.org/ns/activitystreams",
      "https://forgefed.org/ns",
    ])
    activity["type"]?.try(&.as_s?).should eq("Offer")
    activity["actor"]?.try(&.as_s?).should eq("https://forge.example/luke")
    activity["target"]?.try(&.as_s?).should eq("https://dev.example/projects/game-of-life/pr-tracker")
    activity["to"]?.try(&.as_a?).try(&.map(&.as_s)).should eq(["https://dev.example/projects/game-of-life/pr-tracker"])
    activity["cc"]?.try(&.as_a?).try(&.map(&.as_s)).should eq([
      "https://dev.example/projects/game-of-life",
      "https://dev.example/projects/game-of-life/followers",
      "https://dev.example/projects/game-of-life/repo",
      "https://dev.example/projects/game-of-life/repo/followers",
      "https://dev.example/projects/game-of-life/pr-tracker/followers",
    ])

    mr_ticket = activity["object"]?.try(&.as_h?)
    mr_ticket.should_not be_nil
    mr_ticket.not_nil!["type"]?.try(&.as_s?).should eq("Ticket")
    mr_ticket.not_nil!["attributedTo"]?.try(&.as_s?).should eq("https://forge.example/luke")
    mr_ticket.not_nil!["summary"]?.try(&.as_s?).should eq("Fix the animation bug")
    mr_ticket.not_nil!["content"]?.try(&.as_s?).should eq("<p>Please review, thanks!</p>")
    mr_ticket.not_nil!["mediaType"]?.try(&.as_s?).should eq("text/html")

    source = mr_ticket.not_nil!["source"]?.try(&.as_h?)
    source.should_not be_nil
    source.not_nil!["mediaType"]?.try(&.as_s?).should eq("text/markdown; variant=Commonmark")
    source.not_nil!["content"]?.try(&.as_s?).should eq("Please review, thanks!")

    attachment = mr_ticket.not_nil!["attachment"]?.try(&.as_h?)
    attachment.should_not be_nil
    attachment.not_nil!["type"]?.try(&.as_s?).should eq("Offer")

    origin = attachment.not_nil!["origin"]?.try(&.as_h?)
    origin.should_not be_nil
    origin.not_nil!["type"]?.try(&.as_s?).should eq("Branch")
    origin.not_nil!["context"]?.try(&.as_s?).should eq("https://forge.example/luke/game-of-life")
    origin.not_nil!["ref"]?.try(&.as_s?).should eq("refs/heads/fix-animation-bug")

    target = attachment.not_nil!["target"]?.try(&.as_h?)
    target.should_not be_nil
    target.not_nil!["type"]?.try(&.as_s?).should eq("Branch")
    target.not_nil!["context"]?.try(&.as_s?).should eq("https://dev.example/projects/game-of-life/repo")
    target.not_nil!["ref"]?.try(&.as_s?).should eq("refs/heads/main")

    patch_collection = attachment.not_nil!["object"]?.try(&.as_h?)
    patch_collection.should_not be_nil
    patch_collection.not_nil!["type"]?.try(&.as_s?).should eq("OrderedCollection")
    patch_collection.not_nil!["totalItems"]?.try(&.as_i?).should eq(1)
    patches = patch_collection.not_nil!["items"]?.try(&.as_a?)
    patches.should_not be_nil
    patches.not_nil!.size.should eq(1)
    patch = patches.not_nil!.first.as_h
    patch["type"]?.try(&.as_s?).should eq("Patch")
    patch["attributedTo"]?.try(&.as_s?).should eq("https://forge.example/luke")
    patch["mediaType"]?.try(&.as_s?).should eq("application/x-git-patch")
    patch["content"]?.try(&.as_s?).should eq("From c9ae5f4ff4a330b6e1196ceb7db1665bd4c1...")
  end

  it "keeps multiple test PRDs in one outbox array payload" do
    app = ACD::Kemal::App.new(0)
    tickets = [
      JSON.parse(%({
        "type": "Ticket",
        "summary": "PRD-1",
        "source": {"mediaType":"text/markdown; variant=Commonmark","content":"PRD-1"},
        "target": "https://dev.example/projects/game-of-life/pr-tracker"
      })).as_h,
      JSON.parse(%({
        "type": "Ticket",
        "summary": "PRD-2",
        "source": {"mediaType":"text/markdown; variant=Commonmark","content":"PRD-2"},
        "target": "https://dev.example/projects/game-of-life/pr-tracker"
      })).as_h,
    ]

    outputs = [
      {"content" => json_str(%({"type":"Offer","object":{"type":"Ticket","summary":"PRD-1","source":{"mediaType":"text/markdown; variant=Commonmark","content":"PRD-1"},"content":"<p>PRD-1</p>","mediaType":"text/html","attachment":{"type":"Offer","object":{"type":"OrderedCollection","totalItems":1,"items":[{"type":"Patch","mediaType":"application/x-git-patch","content":"diff --git a/a b/a\\n+1"}]}}}})), "status" => json_str("ok")} of String => JSON::Any,
      {"content" => json_str(%({"type":"Offer","object":{"type":"Ticket","summary":"PRD-2","source":{"mediaType":"text/markdown; variant=Commonmark","content":"PRD-2"},"content":"<p>PRD-2</p>","mediaType":"text/html","attachment":{"type":"Offer","object":{"type":"OrderedCollection","totalItems":1,"items":[{"type":"Patch","mediaType":"application/x-git-patch","content":"diff --git a/b b/b\\n+2"}]}}}})), "status" => json_str("ok")} of String => JSON::Any,
    ]

    tickets.zip(outputs).each_with_index do |(ticket, output), idx|
      app.test_publish_result_activity_from_output(
        workflow_id: "solver",
        run_id: "parallel-#{idx + 1}",
        run_status: "ok",
        output: output,
        ticket: ticket,
        requested_activity: "merge",
        remote_actor: "https://dev.example/actors/bot",
        workflow_actor: "https://forge.example/luke",
        local_domain: "https://forge.example",
        published_at: "2026-03-07T00:00:00Z",
      )
    end

    events = app.test_list_outbox_events
    events.size.should eq(2)

    outbox_json = {
      "@context"    => json_str("https://www.w3.org/ns/activitystreams"),
      "type"        => json_str("OrderedCollection"),
      "totalItems"  => json_any(events.size),
      "items"       => json_any(events.map { |entry| entry["activity"]? || JSON.parse("{}") }),
      "orderedItems"=> json_any(events.map { |entry| entry["activity"]? || JSON.parse("{}") }),
    } of String => JSON::Any

    items = outbox_json["items"]?.try(&.as_a?)
    items.should_not be_nil
    items.not_nil!.size.should eq(2)
    summaries = items.not_nil!.compact_map { |entry| entry.as_h?.try(&.["object"]?).try(&.as_h?).try(&.["summary"]?).try(&.as_s?) }
    summaries.sort.should eq(["PRD-1", "PRD-2"])
  end
end
