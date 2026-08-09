require "file_utils"
require "./spec_helper"

# `fedi.internal` is the reserved domain for peers that federate inside one
# deployment. Resolving it must never touch WebFinger, and it must stay
# predictable when a deployment pins peers through the environment.
describe Ocawe::Federation::InternalDomain do
  describe ".parse_peers" do
    it "accepts comma and whitespace separated name=base_url pairs" do
      peers = Ocawe::Federation::InternalDomain.parse_peers(["sender=http://127.0.0.1:4111, receiver=http://127.0.0.1:4222"])

      peers["sender"].should eq("http://127.0.0.1:4111")
      peers["receiver"].should eq("http://127.0.0.1:4222")
    end

    it "drops malformed entries instead of raising, so a typo cannot stop a boot" do
      peers = Ocawe::Federation::InternalDomain.parse_peers(["broken,=http://x,name=,ok=http://127.0.0.1:1/"])

      peers.should eq({"ok" => "http://127.0.0.1:1"})
    end
  end

  describe ".parse_handle" do
    it "accepts both `@name@domain` and `name@domain`" do
      Ocawe::Federation::InternalDomain.parse_handle("@receiver@fedi.internal").should eq({"receiver", "fedi.internal"})
      Ocawe::Federation::InternalDomain.parse_handle("receiver@fedi.internal").should eq({"receiver", "fedi.internal"})
    end

    it "ignores IRIs and bare domains" do
      Ocawe::Federation::InternalDomain.parse_handle("https://example.com/actors/a").should be_nil
      Ocawe::Federation::InternalDomain.parse_handle("fedi.internal").should be_nil
    end
  end

  describe ".resolve_actor" do
    it "prefers the peer map over the service-DNS default" do
      peers = {"receiver" => "http://127.0.0.1:4222"}

      Ocawe::Federation::InternalDomain.resolve_actor("@receiver@fedi.internal", peers)
        .should eq("http://127.0.0.1:4222/actors/receiver")
    end

    it "falls back to `http://<name>.<domain>:4111`, which is what service DNS resolves" do
      Ocawe::Federation::InternalDomain.resolve_actor("@receiver@fedi.internal", {} of String => String)
        .should eq("http://receiver.fedi.internal:4111/actors/receiver")
    end

    it "leaves handles of any other domain alone" do
      Ocawe::Federation::InternalDomain.resolve_actor("@peer@example.com", {} of String => String).should be_nil
    end
  end
end

# The actor identifier comes from the Cawfile `#+name:` header; nothing else in
# the bundle declares it.
describe "federation identity derived from #+name:" do
  it "derives local_actor and local_key_id from the Cawfile name" do
    dir = File.tempname("ocawe_federation_identity")
    Dir.mkdir_p(dir)
    begin
      File.write(File.join(dir, "Cawfile"), <<-RCL)
#+name: sender

settings do
end

struct SenderInput
end

struct SenderOutput
  include Api::Federation::Outbox
end

@[Validate(SenderInput, SenderOutput)]
workflow "13-activitypub-sender" do
  follow ["@receiver@fedi.internal"]
end
RCL

      bundle = ACD::Discovery::CawfileLoader.load_root(dir).not_nil!
      settings = OcaweCore::Utils::ConfigParser.apply_cawfile_settings(Ocawe::Config::Settings.default, bundle)
      settings = OcaweCore::Utils::ConfigParser.apply_federation_identity(settings, bundle, 4111)

      settings.federation.local_actor.should eq("http://127.0.0.1:4111/actors/sender")
      settings.federation.local_key_id.should eq("http://127.0.0.1:4111/actors/sender#main-key")
      # `follow [...]` is the declarative form of an auto subscription.
      settings.federation.auto_subscribe.should contain("@receiver@fedi.internal")
      # `Api::Federation::Outbox` on the output struct is the only federation
      # declaration in the bundle - no `api = [...]` setting exists.
      settings.api.enable?("federation").should be_true
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "keeps an explicitly configured local_actor" do
    dir = File.tempname("ocawe_federation_identity_explicit")
    Dir.mkdir_p(dir)
    begin
      File.write(File.join(dir, "Cawfile"), <<-RCL)
#+name: sender

settings do
  federation.local_actor = "https://example.com/actors/pinned"
end

struct SenderInput
end

struct SenderOutput
end

@[Validate(SenderInput, SenderOutput)]
workflow "pinned" do
end
RCL

      bundle = ACD::Discovery::CawfileLoader.load_root(dir).not_nil!
      settings = OcaweCore::Utils::ConfigParser.apply_cawfile_settings(Ocawe::Config::Settings.default, bundle)
      settings = OcaweCore::Utils::ConfigParser.apply_federation_identity(settings, bundle, 4111)

      settings.federation.local_actor.should eq("https://example.com/actors/pinned")
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
