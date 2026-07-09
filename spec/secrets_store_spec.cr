require "./spec_helper"

describe Ocawe::Secrets do
  it "stores, lists, reads, and deletes scoped secrets without exposing values by default" do
    dir = File.join(Dir.tempdir, "ocawe-secrets-#{Time.utc.to_unix_ms}")
    path = File.join(dir, "secrets.json")
    begin
      entry = Ocawe::Secrets.put(
        "orator/api-keys/demo",
        "orator_test_secret",
        scope: "orator",
        kind: "api_key",
        metadata: {"label" => "demo"},
        path: path
      )
      entry["name"].as_s.should eq("orator/api-keys/demo")
      entry.as_h.has_key?("value").should be_false

      public_entries = Ocawe::Secrets.list(scope: "orator", kind: "api_key", path: path)
      public_entries.size.should eq(1)
      public_entries.first.as_h.has_key?("value").should be_false
      public_entries.first["metadata"]["label"].as_s.should eq("demo")

      private_entries = Ocawe::Secrets.list(scope: "orator", kind: "api_key", include_values: true, path: path)
      private_entries.first["value"].as_s.should eq("orator_test_secret")
      Ocawe::Secrets.value("orator/api-keys/demo", path: path).should eq("orator_test_secret")

      Ocawe::Secrets.delete("orator/api-keys/demo", path: path).should be_true
      Ocawe::Secrets.list(scope: "orator", kind: "api_key", path: path).should be_empty
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end
end
