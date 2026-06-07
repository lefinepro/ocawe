require "ocawe"

module OcaweExamples
  # Creates OcaweCore::AI::AcmeProvider at compile-time.
  OcaweCore::AI.create_custom_provider(
    AcmeProvider,
    "acme",
    "ACME_BASE_URL",
    "ACME_API_KEY",
    "https://acme.example/v1"
  )

  # Example helper showing how to inject custom providers into AI::Client.
  def self.custom_provider_client : OcaweCore::AI::Client
    providers = {
      "acme" => OcaweCore::AI::AcmeProvider.new,
      "openai" => OcaweCore::AI::OpenAIProvider.new,
    } of String => OcaweCore::AI::Provider

    OcaweCore::AI::Client.new(providers)
  end
end
