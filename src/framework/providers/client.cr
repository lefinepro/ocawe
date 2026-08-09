require "json"
require "./model_ref"
require "./provider"
require "./chat_completions_provider"
require "./openai_provider"
require "./gonka_provider"
require "./cli_provider"
require "../telemetry/prompt_metrics"
require "../utils/time_compat"

module OcaweCore
  module AI
    class Client
      def initialize(@providers : Hash(String, Provider)? = nil)
      end

      def generate_text(model_spec : String, prompt : String, system : String? = nil, messages : Array(JSON::Any)? = nil, tools : Array(JSON::Any)? = nil, metadata : AnyHash = {} of String => JSON::Any, api_key : String? = nil, base_url : String? = nil) : TextGenerationResponse
        model = ModelRef.parse(model_spec)
        provider = provider_for(model.provider)
        started = Ocawe::Utils::TimeCompat.monotonic
        status = "success"
        response = nil.as(TextGenerationResponse?)
        begin
          response = provider.generate_text(TextGenerationRequest.new(model: model.model, prompt: prompt, system: system, messages: messages, tools: tools, metadata: metadata, api_key: api_key, base_url: base_url))
          validate_response!(response)
          response
        rescue ex
          status = "error"
          raise ex
        ensure
          latency_ms = Ocawe::Utils::TimeCompat.elapsed_milliseconds(started)
          output_tokens = response ? Ocawe::PromptMetrics.response_tokens(response.text) : 0
          Ocawe::PromptMetrics.record(
            source: "ocawe",
            provider: response.try(&.provider) || model.provider,
            model: response.try(&.model) || model.model,
            prompt: prompt,
            status: status,
            latency_ms: latency_ms,
            context_messages: Ocawe::PromptMetrics.message_count(messages),
            context_chars: Ocawe::PromptMetrics.context_chars(prompt, system, messages),
            output_tokens: output_tokens,
            profile: Ocawe::PromptMetrics.profile_label(metadata),
            session: Ocawe::PromptMetrics.session_label(metadata),
            time_to_response_ms: latency_ms
          )
        end
      end

      private def provider_for(name : String) : Provider
        if providers = @providers
          provider = providers[name]?
          raise "unsupported model provider: #{name}" unless provider
          return provider
        end

        case name
        when "chat_completion"
          ChatCompletionProvider.new
        when "open_responses"
          OpenResponsesProvider.new
        when "gonka"
          GonkaProvider.new
        when "cli"
          CliProvider.new
        else
          ChatCompletionProvider.new
        end
      end

      private def validate_response!(response : TextGenerationResponse) : Nil
        return unless response.text.strip.empty?
        return if response.tool_calls.try { |tool_calls| !tool_calls.empty? }

        raise "model returned an empty response"
      end
    end
  end
end
