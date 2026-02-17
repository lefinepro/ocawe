require "http/client"
require "json"
require "../cognicore/ai/cliproxy_chat_helper"

module Cogni
  module Config
    module DefaultFunctionHandlers
      extend self

      def agent_codex : Cogni::Workflows::Declarative::FunctionHandler
        ->(ctx : Cogni::Workflows::Declarative::NodeContext) do
          prompt = extract_input_text(ctx.input_data["input"]?)
          command = resolve_string_param(ctx, "bin", env_keys: ["CODEX_BIN"], default: "codex") || "codex"
          model = resolve_string_param(ctx, "model", env_keys: ["CODEX_MODEL"])
          passthrough = resolve_string_array_param(ctx, "args")

          args = ["exec"] of String
          if model && !has_model_flag?(passthrough)
            args << "--model"
            args << model
          end
          args.concat(passthrough)

          stdout = IO::Memory.new
          stderr = IO::Memory.new
          input = IO::Memory.new(prompt)

          status = Process.run(command, args: args, input: input, output: stdout, error: stderr)
          if status.success?
            Cogni::Workflows::Declarative::AgentResult.new(
              agent_type: "function",
              content: stdout.to_s.strip,
              metadata: {
                "engine"  => any("codex"),
                "command" => any("#{command} #{args.join(" ")}"),
                "model"   => any(model || ""),
              } of String => JSON::Any,
            )
          else
            Cogni::Workflows::Declarative::AgentResult.new(
              agent_type: "function",
              content: "codex exec failed: #{stderr.to_s.strip}",
              metadata: {
                "engine"      => any("codex"),
                "status_code" => any(status.exit_code),
                "model"       => any(model || ""),
              } of String => JSON::Any,
            )
          end
        rescue ex
          Cogni::Workflows::Declarative::AgentResult.new(
            agent_type: "function",
            content: "codex exec error: #{ex.message}",
          )
        end
      end

      def agent_cliproxy : Cogni::Workflows::Declarative::FunctionHandler
        ->(ctx : Cogni::Workflows::Declarative::NodeContext) do
          prompt = extract_input_text(ctx.input_data["input"]?)
          system = resolve_string_param(ctx, "system")
          base_url = resolve_string_param(ctx, "base_url", env_keys: ["CLIPROXY_API_BASE", "CLIPROXY_API_URL"], default: CogniCore::AI::CLIProxyChatHelper::DEFAULT_BASE_URL) || CogniCore::AI::CLIProxyChatHelper::DEFAULT_BASE_URL
          model = resolve_string_param(ctx, "model", env_keys: ["CLIPROXY_MODEL"], default: "qwen3-coder-plus") || "qwen3-coder-plus"
          api_key = resolve_string_param(ctx, "api_key", env_keys: ["CLIPROXY_API_KEY"])

          response = CogniCore::AI::CLIProxyChatHelper.generate_text(
            provider_name: "cliproxyapi",
            model: model,
            prompt: prompt,
            system: system,
            api_key: api_key,
            base_url: base_url,
          )

          Cogni::Workflows::Declarative::AgentResult.new(
            agent_type: "function",
            content: response.text,
            provider: response.provider,
            model: "#{response.provider}/#{response.model}",
            metadata: {
              "engine"   => any("cliproxyapi"),
              "base_url" => any(base_url),
              "model"    => any(model),
            } of String => JSON::Any,
          )
        rescue ex
          Cogni::Workflows::Declarative::AgentResult.new(
            agent_type: "function",
            content: "cliproxy error: #{ex.message}",
          )
        end
      end

      # OpenCode server API: POST /session then POST /session/:id/message.
      def agent_opencode : Cogni::Workflows::Declarative::FunctionHandler
        ->(ctx : Cogni::Workflows::Declarative::NodeContext) do
          prompt = extract_input_text(ctx.input_data["input"]?)
          base_url = resolve_string_param(ctx, "base_url", env_keys: ["OPENCODE_API_BASE", "OPENCODE_API_URL"], default: "http://127.0.0.1:4096") || "http://127.0.0.1:4096"
          api_key = resolve_string_param(ctx, "api_key", env_keys: ["OPENCODE_API_KEY"])
          model = resolve_string_param(ctx, "model", env_keys: ["OPENCODE_MODEL"])

          headers = HTTP::Headers{"Content-Type" => "application/json"}
          headers["Authorization"] = "Bearer #{api_key}" if api_key

          session_response = HTTP::Client.post(
            join_url(base_url, "/session"),
            headers: headers,
            body: "{}"
          )
          unless session_response.success?
            return Cogni::Workflows::Declarative::AgentResult.new(
              agent_type: "function",
              content: "opencode session create failed (#{session_response.status_code}): #{session_response.body}",
            )
          end

          session_id = parse_session_id(session_response.body)
          unless session_id
            return Cogni::Workflows::Declarative::AgentResult.new(
              agent_type: "function",
              content: "opencode session id not found in response",
            )
          end

          message_payload = {
            "parts" => any([{type: "text", text: prompt}]),
          } of String => JSON::Any
          message_payload["model"] = any(model) if model

          message_response = HTTP::Client.post(
            join_url(base_url, "/session/#{session_id}/message"),
            headers: headers,
            body: message_payload.to_json
          )

          content = if message_response.success?
                      parse_opencode_message_content(message_response.body) || message_response.body
                    else
                      "opencode message failed (#{message_response.status_code}): #{message_response.body}"
                    end

          Cogni::Workflows::Declarative::AgentResult.new(
            agent_type: "function",
            content: content,
            metadata: {
              "engine"     => any("opencode"),
              "session_id" => any(session_id),
              "base_url"   => any(base_url),
              "model"      => any(model || ""),
            } of String => JSON::Any,
          )
        rescue ex
          Cogni::Workflows::Declarative::AgentResult.new(
            agent_type: "function",
            content: "opencode error: #{ex.message}",
          )
        end
      end

      private def extract_input_text(input : JSON::Any?) : String
        return "" unless input
        if text = input.as_s?
          return text
        end
        if hash = input.as_h?
          return hash["content"]?.try(&.as_s?) || hash["text"]?.try(&.as_s?) || input.to_json
        end
        input.to_json
      end

      private def join_url(base_url : String, path : String) : String
        base = base_url.ends_with?("/") ? base_url[0, base_url.size - 1] : base_url
        "#{base}#{path}"
      end

      private def has_model_flag?(args : Array(String)) : Bool
        args.any? { |arg| arg == "--model" || arg == "-m" || arg.starts_with?("--model=") }
      end

      private def resolve_string_param(
        ctx : Cogni::Workflows::Declarative::NodeContext,
        key : String,
        env_keys : Array(String) = [] of String,
        default : String? = nil
      ) : String?
        if value = param_from_ctx(ctx, key)
          if string = value.as_s?
            return string
          end
        end

        env_keys.each do |env_key|
          env_val = ENV[env_key]?
          return env_val if env_val && !env_val.empty?
        end

        default
      end

      private def resolve_string_array_param(ctx : Cogni::Workflows::Declarative::NodeContext, key : String) : Array(String)
        value = param_from_ctx(ctx, key)
        return [] of String unless value

        if entries = value.as_a?
          return entries.compact_map(&.as_s?)
        end

        if single = value.as_s?
          return [single]
        end

        [] of String
      end

      private def param_from_ctx(ctx : Cogni::Workflows::Declarative::NodeContext, key : String) : JSON::Any?
        direct = ctx.input_data[key]?
        return direct if direct

        input_payload = ctx.input_data["input"]?.try(&.as_h?)
        if input_payload
          return input_payload[key]? if input_payload[key]?
        end

        nil
      end

      private def parse_session_id(body : String) : String?
        parsed = JSON.parse(body).as_h?
        return nil unless parsed
        parsed["id"]?.try(&.as_s?) ||
          parsed["sessionID"]?.try(&.as_s?) ||
          parsed["session_id"]?.try(&.as_s?) ||
          parsed["session"]?.try(&.as_h?).try(&.["id"]?).try(&.as_s?)
      rescue
        nil
      end

      private def parse_opencode_message_content(body : String) : String?
        parsed = JSON.parse(body).as_h?
        return nil unless parsed
        content = parsed["content"]?.try(&.as_s?)
        return content if content
        text = parsed["text"]?.try(&.as_s?)
        return text if text

        parts = parsed["parts"]?.try(&.as_a?)
        if parts
          joined = parts.compact_map { |part| part.as_h?.try(&.["text"]?).try(&.as_s?) }.join("\n")
          return joined unless joined.empty?
        end

        message = parsed["message"]?.try(&.as_h?)
        if message
          direct = message["content"]?.try(&.as_s?) || message["text"]?.try(&.as_s?)
          return direct if direct
          msg_parts = message["parts"]?.try(&.as_a?)
          if msg_parts
            joined = msg_parts.compact_map { |part| part.as_h?.try(&.["text"]?).try(&.as_s?) }.join("\n")
            return joined unless joined.empty?
          end
        end
        nil
      rescue
        nil
      end

      private def any(value) : JSON::Any
        JSON.parse(value.to_json)
      end
    end
  end
end
