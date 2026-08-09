require "./federation_e2e_helper"

# Cross-process ActivityPub (S2S) end-to-end test.
#
# This is deliberately *not* the in-process multi-agent chain covered by
# `spec/e2e/agent_interaction_spec.cr`: here two separate `ocawecore` OS
# processes federate over loopback HTTP, so the assertions exercise actor
# discovery, HTTP Signature verification, inbox ingestion, inbox idempotency and
# outbox correlation instead of in-process node wiring.
#
#   Agent A process  --(classic run API)-->  A's mock agent run
#     -> signed ActivityPub Create(Ticket)  --HTTP-->  Agent B's discovered inbox
#     -> Agent B mock agent run (exactly once)
#     -> Agent B outbox Create(Note), correlated by `object.inReplyTo`
#
# Coverage boundary (R-017): the `Create(Ticket)` envelope is assembled by the
# test after Agent A's run has produced its output, using Aptok's own vocabulary
# builders, and is delivered and signed with Agent A's key by `Aptok::Transport`
# - the same library and egress path the runtime federates with (R-007).
# Ocawe's outbound federation path (`publish_outbound_federation_output`) only
# emits an activity when a run produces `federation_output.activity`, and no
# currently supported node kind produces that from a plain agent run, so
# reproducing it here would have required a new production surface (explicitly
# out of scope). Everything downstream of the signed HTTP POST — signature
# verification, routing, execution, result publication — is production code.
#
# That outbound half is covered separately by
# `spec/e2e/activitypub_cawfile_send_spec.cr`, where an `exec` node in the
# committed `caws/13-activitypub` example produces `federation_output.activity`
# and the runtime itself signs and delivers it. This spec keeps its own
# test-built envelope on purpose: it pins the inbound contract independently of
# whatever a workflow happens to emit.
#
# Sender trigger mechanism (the issue's "public trigger vs API mode" ambiguity,
# recorded deliberately): the already supported classic run endpoint
# `POST /v1/workflows/:workflowId/runs`. It stays mounted alongside the
# federation routes because a bundle that declares `Api::Federation::Inbox`
# resolves to `api = ["classic", "federation"]`, which is not `federation_only?`.
describe "ActivityPub cross-process agent-to-agent federation (two OS processes)" do
  it "runs Agent A, delivers a signed Create(Ticket) to Agent B's discovered inbox, and correlates Agent B's Create(Note) reply" do
    FederationE2E::Harness.run do |harness|
      sender = harness.sender
      receiver = harness.receiver

      # --- R-002 / AC-001: two genuinely isolated peers -----------------------
      sender.pid.should_not eq(receiver.pid)
      sender.port.should_not eq(receiver.port)
      sender.root.should_not eq(receiver.root)
      sender.workflow_id.should_not eq(receiver.workflow_id)
      sender.actor_url.should_not eq(receiver.actor_url)
      sender.private_key_path.should_not eq(receiver.private_key_path)
      File.read(sender.private_key_path).should_not eq(File.read(receiver.private_key_path))
      sender.running?.should be_true
      receiver.running?.should be_true

      # --- R-005 / AC-002: discover both actors over HTTP ---------------------
      sender_actor = harness.actor_document(sender)
      receiver_actor = harness.actor_document(receiver)

      [{sender, sender_actor}, {receiver, receiver_actor}].each do |peer, document|
        document["id"]?.try(&.as_s?).should eq(peer.actor_url)
        document["type"]?.try(&.as_s?).should eq("Application")
        document["inbox"]?.try(&.as_s?).should eq(peer.inbox_url)
        document["outbox"]?.try(&.as_s?).should eq(peer.outbox_url)

        public_key = document["publicKey"]?.try(&.as_h?)
        public_key.should_not be_nil
        public_key = public_key.not_nil!
        public_key["id"]?.try(&.as_s?).should eq(peer.key_id)
        public_key["owner"]?.try(&.as_s?).should eq(peer.actor_url)
        public_key["publicKeyPem"]?.try(&.as_s?).to_s.should contain("BEGIN PUBLIC KEY")
      end

      sender_actor["id"].should_not eq(receiver_actor["id"])
      sender_actor["publicKey"].should_not eq(receiver_actor["publicKey"])

      # Delivery target and signing identity come from the discovered documents,
      # never from hardcoded strings.
      receiver_inbox = receiver_actor["inbox"].as_s
      sender_key_id = sender_actor["publicKey"].as_h["id"].as_s
      signing_key = Aptok::ActorKeyPair.new(
        id: sender_key_id,
        owner: sender_actor["id"].as_s,
        public_key_pem: "",
        private_key_path: sender.private_key_path,
      )

      # --- R-004 / R-006 / AC-003: run Agent A in mock mode -------------------
      marker = FederationE2E.unique_marker("ticket")
      sender_snapshot = harness.start_run(
        sender,
        "Draft one short sentence for the peer agent and repeat the marker #{marker} verbatim."
      )
      sender_snapshot["status"]?.try(&.as_s?).should eq("success")

      sender_output = sender_snapshot["output"]?.try(&.as_h?)
      sender_output.should_not be_nil
      sender_text = sender_output.not_nil!["last_response"]?.try(&.as_s?).to_s
      sender_text.should match(FederationE2E::MOCK_SIGNATURE)
      sender_text.should contain(marker)

      # --- R-007: signed Create(Ticket) built from Agent A's real output ------
      # The envelope is assembled by Aptok's vocabulary builders and delivered
      # by `Aptok::Transport`, so the wire shape and the HTTP Signature come
      # from the library the runtime federates with, not from this spec.
      delivery_config = Aptok::DeliveryConfig.new(
        inbox: receiver_inbox,
        actor: sender.actor_url,
        target: receiver.actor_url,
      )
      create_activity = FederationE2E.build_ticket_activity(
        Aptok::PublishRequest.new(
          title: "E2E federated task #{marker}",
          content: sender_text,
          assignee: receiver.actor_url,
          attributed_to: sender.actor_url,
        ),
        delivery_config,
      )

      create_activity["type"].as_s.should eq("Create")
      ticket = create_activity["object"].as_h
      ticket["type"].as_s.should eq("Ticket")
      ticket_id = ticket["id"].as_s
      # The ticket is what carries Agent A's output across the wire (R-006).
      ticket["content"].as_s.should contain(marker)
      ticket["name"].as_s.empty?.should be_false
      ticket["assignee"].as_s.should eq(receiver.actor_url)

      receiver_runs_before = harness.runs(receiver).size

      # --- R-008 / AC-004: signed delivery to the discovered inbox ------------
      delivery = FederationE2E.deliver(delivery_config, create_activity, signing_key)
      delivery.status.should eq(202)
      delivery.body.should contain("enqueued")

      # --- R-008 / AC-005: the receiver executes exactly once -----------------
      harness.wait_until("Agent B to execute the delivered ticket exactly once") do
        runs = harness.runs(receiver)
        executed = runs.size - receiver_runs_before
        next "Agent B has not executed yet (#{runs.size} runs total)" if executed < 1
        next "Agent B executed #{executed} times, expected exactly 1" if executed > 1
        pending = runs.select { |run| run.as_h["status"]?.try(&.as_s?) == "running" }
        next "Agent B run is still running" unless pending.empty?
        nil
      end

      # --- R-009 / AC-006: correlated Create(Note) in Agent B's outbox --------
      note_activity : Hash(String, JSON::Any)? = nil
      harness.wait_until("Agent B to publish a Create(Note) replying to #{ticket_id}") do
        replies = FederationE2E.notes_replying_to(harness.outbox_activities(receiver), ticket_id)
        next "no Create(Note) with inReplyTo=#{ticket_id} yet" if replies.empty?
        next "#{replies.size} Create(Note) activities reply to #{ticket_id}, expected exactly 1" if replies.size > 1
        note_activity = replies.first
        nil
      end

      note_activity.should_not be_nil
      published = note_activity.not_nil!
      published["type"].as_s.should eq("Create")
      published["actor"].as_s.should eq(receiver.actor_url)
      published["id"].as_s.should start_with(receiver.base_url)

      note = published["object"].as_h
      note["type"].as_s.should eq("Note")
      note["inReplyTo"].as_s.should eq(ticket_id)
      note["id"].as_s.should start_with(receiver.base_url)

      # Agent B's own mock run wrapped Agent A's mock output, so the reply
      # carries two mock signatures. One would mean the receiver echoed the
      # inbound ticket instead of publishing its own answer.
      note_content = note["content"].as_s
      note_content.should contain(marker)
      note_content.scan(FederationE2E::MOCK_SIGNATURE).size.should eq(2)

      # --- R-010 / AC-007: replaying the identical activity is idempotent -----
      replay = FederationE2E.deliver(delivery_config, create_activity, signing_key)
      replay.status.should eq(202)

      runs_after_first_delivery = harness.runs(receiver).size
      notes_after_first_delivery = 1

      # Give the federation poller several cycles to (not) process the replay.
      FederationE2E.settle(harness.receiver_poll_settle_time)

      harness.runs(receiver).size.should eq(runs_after_first_delivery)
      FederationE2E.notes_replying_to(harness.outbox_activities(receiver), ticket_id)
        .size.should eq(notes_after_first_delivery)

      # --- R-011 / AC-008: unsigned delivery is rejected, state unchanged -----
      outbox_before_unsigned = harness.outbox_activities(receiver).size
      # A fresh envelope (new ids), so a rejection can never be mistaken for the
      # idempotent replay above. Built by the same Aptok path, delivered with no
      # key pair, which is what makes it unsigned.
      unsigned_activity = FederationE2E.build_ticket_activity(
        Aptok::PublishRequest.new(
          title: "E2E unsigned task #{marker}",
          content: "unsigned #{marker}",
          assignee: receiver.actor_url,
          attributed_to: sender.actor_url,
        ),
        delivery_config,
      )
      unsigned_ticket_id = unsigned_activity["object"].as_h["id"].as_s
      unsigned_ticket_id.should_not eq(ticket_id)

      unsigned = FederationE2E.deliver(delivery_config, unsigned_activity, nil)
      unsigned.status.should eq(401)

      FederationE2E.settle(harness.receiver_poll_settle_time)

      harness.runs(receiver).size.should eq(runs_after_first_delivery)
      harness.outbox_activities(receiver).size.should eq(outbox_before_unsigned)
      FederationE2E.notes_replying_to(harness.outbox_activities(receiver), unsigned_ticket_id)
        .should be_empty

      # Both peers survived the whole scenario; a crashed child would otherwise
      # be reported as a timeout further up.
      sender.running?.should be_true
      receiver.running?.should be_true
    end
  end
end
