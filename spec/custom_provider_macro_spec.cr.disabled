require "./spec_helper"

OcaweCore::AI.create_custom_provider(
  TestMacroProvider,
  "testmacro",
  "TESTMACRO_BASE_URL",
  "TESTMACRO_API_KEY",
  "http://127.0.0.1:9999/v1"
)

describe "OcaweCore::AI.create_custom_provider" do
  it "generates a provider class compatible with AI::Client" do
    old = ENV["COGNICORE_MOCK_LLM"]?
    begin
      ENV["COGNICORE_MOCK_LLM"] = "1"

      providers = {
        "testmacro" => OcaweCore::AI::TestMacroProvider.new,
      } of String => OcaweCore::AI::Provider

      response = OcaweCore::AI::Client.new(providers).generate_text(
        "testmacro/demo-model",
        "hello from macro"
      )

      response.provider.should eq("testmacro")
      response.model.should eq("demo-model")
      response.text.should contain("[mock testmacro]")
    ensure
      if old
        ENV["COGNICORE_MOCK_LLM"] = old
      else
        ENV.delete("COGNICORE_MOCK_LLM")
      end
    end
  end
end
