require "cogni"

module CogniExamples
  # Creates CogniCore::AI::AcmeProvider at compile-time.
  CogniCore::AI.create_custom_provider(
    AcmeProvider,
    "acme",
    "ACME_BASE_URL",
    "ACME_API_KEY",
    "https://acme.example/v1"
  )

  # Example helper showing how to inject custom providers into AI::Client.
  def self.custom_provider_client : CogniCore::AI::Client
    providers = {
      "acme" => CogniCore::AI::AcmeProvider.new,
      "openai" => CogniCore::AI::OpenAIProvider.new,
    } of String => CogniCore::AI::Provider

    CogniCore::AI::Client.new(providers)
  end
end
