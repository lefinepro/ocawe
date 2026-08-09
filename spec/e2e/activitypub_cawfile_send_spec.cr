require "./federation_e2e_helper"

# End-to-end test for the committed Cawfile example `caws/13-activitypub`.
#
# Unlike `spec/e2e/activitypub_agent_communication_spec.cr`, where the spec
# itself assembles and signs the outbound `Create(Ticket)`, here *both peers are
# Cawfiles*: nothing in this file builds, signs, POSTs or even triggers an
# activity. The sender workflow is `@[Service]`, so the runtime starts it once at
# boot; everything after that - resolving `@receiver@fedi.internal`, following
# it, building the activity from `publish`, appending it to the outbox, signing
# and delivering - is production code driven by the example bundle.
#
#   sender Cawfile (`follow` + `publish`) -> `federation_output.activity`
#     -> outbound delivery to the followed inbox, HTTP-signed
#     -> receiver Cawfile runs its agent exactly once
#     -> receiver outbox `Create(Note)`, correlated by `object.inReplyTo`
#
# Neither bundle configures an API: federation is enabled purely by the
# `Api::Federation::Outbox` / `Api::Federation::Inbox` types they declare. Every
# assertion below reads the public ActivityPub surface only, so the test proves
# the send without depending on the classic run API at all.
#
# The bundles are copied out of the repository and only their demo ports, the
# published content marker and the model annotation are rewritten per run (see
# `Harness.new_example`), so an edit that breaks the example breaks this spec.
describe "ActivityPub send from a Cawfile (caws/13-activitypub)" do
  it "delivers the published Create(Ticket) to the followed peer and correlates the reply" do
    FederationE2E::Harness.run_example do |harness|
      sender = harness.sender
      receiver = harness.receiver
      marker = harness.marker

      sender.workflow_id.should eq("13-activitypub-sender")
      receiver.workflow_id.should eq("13-activitypub-receiver")
      # The actor is derived from the Cawfile `#+name:` header, not the id.
      sender.actor_url.should eq("#{sender.base_url}/actors/sender")
      receiver.actor_url.should eq("#{receiver.base_url}/actors/receiver")
      sender.port.should_not eq(receiver.port)

      # `follow ["@receiver@fedi.internal"]` resolves through the internal peer
      # map, so the receiver's actor document has to be served first.
      receiver_actor = harness.actor_document(receiver)
      receiver_actor["inbox"]?.try(&.as_s?).should eq(receiver.inbox_url)

      # The signing key was never provisioned by the harness: the example
      # declares none, so each runtime generated its own on first use. Without
      # it, `publicKey.publicKeyPem` below would be absent and no delivery could
      # be signed.
      receiver_actor["publicKey"].as_h["publicKeyPem"].as_s.should start_with("-----BEGIN")
      harness.actor_document(sender)["publicKey"].as_h["publicKeyPem"].as_s.should start_with("-----BEGIN")

      # --- the Cawfile's own activity landed in the sender's outbox -----------
      ticket_activity : Hash(String, JSON::Any)? = nil
      harness.wait_until("the sender Cawfile to publish its Create(Ticket) carrying #{marker}") do
        candidates = FederationE2E.tickets_containing(harness.outbox_activities(sender), marker)
        next "no Create(Ticket) with the marker in the sender outbox yet" if candidates.empty?
        next "#{candidates.size} Create(Ticket) activities carry the marker, expected exactly 1" if candidates.size > 1
        ticket_activity = candidates.first
        nil
      end

      published = ticket_activity.not_nil!
      published["actor"].as_s.should eq(sender.actor_url)
      ticket = published["object"].as_h
      ticket["assignee"].as_s.should eq(receiver.actor_url)
      ticket["name"].as_s.empty?.should be_false
      ticket_id = ticket["id"].as_s
      ticket_id.empty?.should be_false

      # --- correlated Create(Note) reply --------------------------------------
      note_activity : Hash(String, JSON::Any)? = nil
      harness.wait_until("the receiver to publish a Create(Note) replying to #{ticket_id}") do
        replies = FederationE2E.notes_replying_to(harness.outbox_activities(receiver), ticket_id)
        next "no Create(Note) with inReplyTo=#{ticket_id} yet" if replies.empty?
        next "#{replies.size} Create(Note) activities reply to #{ticket_id}, expected exactly 1" if replies.size > 1
        note_activity = replies.first
        nil
      end

      reply = note_activity.not_nil!
      reply["actor"].as_s.should eq(receiver.actor_url)
      note = reply["object"].as_h
      note["type"].as_s.should eq("Note")
      note["id"].as_s.should start_with(receiver.base_url)

      # The receiver's own agent answered: a mock signature proves the reply is
      # a fresh agent run rather than the inbound ticket echoed back.
      note["content"].as_s.should match(FederationE2E::MOCK_SIGNATURE)

      # --- exactly once -------------------------------------------------------
      # Without querying any run API, "the receiver executed exactly once" is
      # proven on the public outbox: several full poll cycles later there is
      # still exactly one reply, and the sender still published exactly one
      # ticket (no duplicate delivery, no re-run of the `@[Service]` workflow).
      sleep harness.receiver_poll_settle_time

      FederationE2E.notes_replying_to(harness.outbox_activities(receiver), ticket_id).size.should eq(1)
      FederationE2E.tickets_containing(harness.outbox_activities(sender), marker).size.should eq(1)

      # The delivery was accepted over a verified HTTP Signature: both peers run
      # with `federation.signatures_required = true`, so an unsigned or
      # wrongly-signed POST would never have reached the receiver's workflow.
      sender.running?.should be_true
      receiver.running?.should be_true
    end
  end
end
