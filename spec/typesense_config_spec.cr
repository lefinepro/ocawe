require "./spec_helper"
require "../../../src/integration/typesense-api"

describe CogniCore::Integration::TypesenseApi::Config do
  it "loads required env and defaults collection" do
    env = {
      "TYPESENSE_URL" => "http://localhost:8108/",
      "TYPESENSE_API_KEY" => "secret",
    } of String => String

    config = CogniCore::Integration::TypesenseApi::Config.from_env(env)
    config.url.should eq("http://localhost:8108")
    config.api_key.should eq("secret")
    config.collection.should eq("materials")
  end

  it "requires url and api key" do
    expect_raises(CogniCore::Integration::TypesenseApi::ConfigError, /TYPESENSE_URL/) do
      CogniCore::Integration::TypesenseApi::Config.from_env({"TYPESENSE_API_KEY" => "k"} of String => String)
    end

    expect_raises(CogniCore::Integration::TypesenseApi::ConfigError, /TYPESENSE_API_KEY/) do
      CogniCore::Integration::TypesenseApi::Config.from_env({"TYPESENSE_URL" => "http://localhost:8108"} of String => String)
    end
  end
end
