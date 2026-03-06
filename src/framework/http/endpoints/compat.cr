module ACD
  module Kemal
    class App
      private def mount_compat_endpoints
        post "/v1/responses" { |env| not_implemented(env, "responses endpoint pending Kemal integration") }
        post "/v1/chat/completions" do |env|
          body = json_body(env)
          model = body["model"]?.try(&.as_s?) || FALLBACK_CHAT_MODEL
          messages = extract_chat_messages(body)
          prompt = chat_prompt_from_messages(messages, body)
          system_message = chat_system_message(messages, body)
          metadata = body["metadata"]?.try(&.as_h?) || {} of String => JSON::Any

          begin
            response = CogniCore::AI::Client.new.generate_text(
              model_spec: model,
              prompt: prompt,
              system: system_message,
              metadata: metadata,
            )
          rescue ex
            env.response.status_code = 422
            env.response.content_type = "application/json"
            next({error: {type: "generation_error", message: ex.message || "chat completion failed"}}.to_json)
          end

          now = Time.utc.to_unix
          env.response.content_type = "application/json"
          {
            "id" => "chatcmpl_#{Random::Secure.hex(12)}",
            "object" => "chat.completion",
            "created" => now,
            "model" => response.model,
            "choices" => [
              {
                "index" => 0,
                "message" => {
                  "role" => "assistant",
                  "content" => response.text,
                },
                "finish_reason" => "stop",
              },
            ],
            "usage" => {
              "prompt_tokens" => 0,
              "completion_tokens" => 0,
              "total_tokens" => 0,
            },
          }.to_json
        end
      end
    end
  end
end
