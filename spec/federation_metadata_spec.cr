require "./spec_helper"

describe "ACD::Kemal::App federation metadata" do
  it "parses supported FEPs from FEDERATION.md" do
    original_metadata_path = ENV["COGNI_FEDERATION_MD"]?
    ENV["COGNI_FEDERATION_MD"] = File.expand_path("FEDERATION.md", Dir.current)

    app = ACD::Kemal::App.new(0)
    metadata = app.test_federation_metadata_document

    protocols = metadata["protocols"]?.try(&.as_a?) || [] of JSON::Any
    protocols.any? { |entry| entry.as_s? == "https://www.w3.org/ns/activitystreams" }.should be_true
    protocols.any? { |entry| entry.as_s? == "https://forgefed.org/ns" }.should be_true

    feps = metadata["supported_feps"]?.try(&.as_a?)
    feps.should_not be_nil
    fep_ids = feps.not_nil!.map do |entry|
      entry.as_h?.try(&.["id"]?.try(&.as_s?)).to_s
    end
    fep_ids.includes?("FEP-67FF").should be_true
    fep_ids.includes?("FEP-EF61").should be_true
  ensure
    if original_metadata_path.nil?
      ENV.delete("COGNI_FEDERATION_MD")
    else
      ENV["COGNI_FEDERATION_MD"] = original_metadata_path
    end
  end
end
