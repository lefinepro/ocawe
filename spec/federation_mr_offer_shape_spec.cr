require "./spec_helper"

describe "ACD::Kemal::App federation merge request format" do
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
      "@context"     => json_str("https://www.w3.org/ns/activitystreams"),
      "type"         => json_str("OrderedCollection"),
      "totalItems"   => json_any(events.size),
      "items"        => json_any(events.map { |entry| entry["activity"]? || JSON.parse("{}") }),
      "orderedItems" => json_any(events.map { |entry| entry["activity"]? || JSON.parse("{}") }),
    } of String => JSON::Any

    items = outbox_json["items"]?.try(&.as_a?)
    items.should_not be_nil
    items.not_nil!.size.should eq(2)
    summaries = items.not_nil!.compact_map { |entry| entry.as_h?.try(&.["object"]?).try(&.as_h?).try(&.["summary"]?).try(&.as_s?) }
    summaries.sort.should eq(["PRD-1", "PRD-2"])
  end
end
