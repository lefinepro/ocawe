require "./spec_helper"
require "file_utils"
require "../src/cli/endpoints/runtime"

describe OcaweCore::CLI::ContainerCredentials do
  it "mounts an explicit Codex home read-only without embedding it in the image" do
    home = File.tempname("ocawe_codex_home")
    Dir.mkdir_p(home)
    begin
      File.write(File.join(home, "auth.json"), "{}")
      args = OcaweCore::CLI::ContainerCredentials.arguments({"CODEX_HOME" => home})
      args.should eq([
        "--env", "CODEX_HOME=/run/ocawe/credentials/codex",
        "--tmpfs", "/run/ocawe/credentials/codex",
        "--volume", "#{File.join(File.expand_path(home), "auth.json")}:/run/ocawe/credentials/codex/auth.json:ro",
      ])
    ensure
      FileUtils.rm_rf(home)
    end
  end

  it "does not add credentials when CODEX_HOME or auth.json is unavailable" do
    OcaweCore::CLI::ContainerCredentials.arguments({} of String => String).should be_empty
    OcaweCore::CLI::ContainerCredentials.arguments({"CODEX_HOME" => "/missing/ocawe-codex-home"}).should be_empty
  end
end

describe OcaweCore::CLI::ContainerFederationEnvironment do
  it "forwards only declared federation metadata" do
    args = OcaweCore::CLI::ContainerFederationEnvironment.arguments({
      "OCAWE_FEDERATION_RESOURCE_CONFORMS_TO" => "https://fmatch/marketplace/resources/model",
      "OCAWE_FEDERATION_TAGS" => "model,code",
      "OPENAI_API_KEY" => "must-not-be-forwarded",
    })

    args.should eq([
      "--env", "OCAWE_FEDERATION_RESOURCE_CONFORMS_TO=https://fmatch/marketplace/resources/model",
      "--env", "OCAWE_FEDERATION_TAGS=model,code",
    ])
  end
end
