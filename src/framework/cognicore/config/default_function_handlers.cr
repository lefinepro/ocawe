require "http/client"

module CogniCore
  module Config
    module DefaultFunctionHandlers
      extend self

      def agent_codex : CogniCore::Workflow::FunctionHandler
        ->(ctx : CogniCore::Workflow::NodeContext) do
          prompt = extract_input_text(ctx.input_data["input"]?)
          command = ENV["CODEX_BIN"]? || "codex"
          args = ["exec"] of String
          stdout = IO::Memory.new
          stderr = IO::Memory.new
          input = IO::Memory.new(prompt)

          status = Process.run(command, args: args, input: input, output: stdout, error: stderr)
          if status.success?
            CogniCore::Workflow::AgentResult.new(
              agent_type: "function",
              content: stdout.to_s.strip,
              metadata: {
                "engine" => JSON.parse("codex".to_json),
                "command" => JSON.parse("#{command} #{args.join(" ")}".to_json),
              } of String => JSON::Any,
            )
          else
            CogniCore::Workflow::AgentResult.new(
              agent_type: "function",
              content: "codex exec failed: #{stderr.to_s.strip}",
              metadata: {
                "engine" => JSON.parse("codex".to_json),
                "status_code" => JSON.parse(status.exit_code.to_json),
              } of String => JSON::Any,
            )
          end
        rescue ex
          CogniCore::Workflow::AgentResult.new(
            agent_type: "function",
            content: "codex exec error: #{ex.message}",
          )
        end
      end

      # OpenAI API v1-compatible proxy call.
      def agent_cliproxy : CogniCore::Workflow::FunctionHandler
        ->(ctx : CogniCore::Workflow::NodeContext) do
          prompt = extract_input_text(ctx.input_data["input"]?)
          base_url = ENV["CLIPROXY_API_BASE"]? || ENV["CLIPROXY_API_URL"]? || "http://127.0.0.1:8080"
          model = ENV["CLIPROXY_MODEL"]? || "gpt-4.1-mini"
          api_key = ENV["CLIPROXY_API_KEY"]?

          headers = HTTP::Headers{"Content-Type" => "application/json"}
          headers["Authorization"] = "Bearer #{api_key}" if api_key

          payload = {
            "model" => JSON.parse(model.to_json),
            "messages" => JSON.parse([{role: "user", content: prompt}].to_json),
          } of String => JSON::Any

          response = HTTP::Client.post(
            join_url(base_url, "/v1/chat/completions"),
            headers: headers,
            body: payload.to_json
          )

          content = if response.success?
                      parse_openai_chat_content(response.body) || response.body
                    else
                      "cliproxy request failed (#{response.status_code}): #{response.body}"
                    end

          CogniCore::Workflow::AgentResult.new(
            agent_type: "function",
            content: content,
            metadata: {
              "engine" => JSON.parse("cliproxy".to_json),
              "base_url" => JSON.parse(base_url.to_json),
            } of String => JSON::Any,
          )
        rescue ex
          CogniCore::Workflow::AgentResult.new(
            agent_type: "function",
            content: "cliproxy error: #{ex.message}",
          )
        end
      end

      # OpenCode server API: POST /session then POST /session/:id/message.
      def agent_opencode : CogniCore::Workflow::FunctionHandler
        ->(ctx : CogniCore::Workflow::NodeContext) do
          prompt = extract_input_text(ctx.input_data["input"]?)
          base_url = ENV["OPENCODE_API_BASE"]? || ENV["OPENCODE_API_URL"]? || "http://127.0.0.1:4096"
          api_key = ENV["OPENCODE_API_KEY"]?
          headers = HTTP::Headers{"Content-Type" => "application/json"}
          headers["Authorization"] = "Bearer #{api_key}" if api_key

          session_response = HTTP::Client.post(
            join_url(base_url, "/session"),
            headers: headers,
            body: {} of String => JSON::Any
          )
          unless session_response.success?
            return CogniCore::Workflow::AgentResult.new(
              agent_type: "function",
              content: "opencode session create failed (#{session_response.status_code}): #{session_response.body}",
            )
          end

          session_id = parse_session_id(session_response.body)
          unless session_id
            return CogniCore::Workflow::AgentResult.new(
              agent_type: "function",
              content: "opencode session id not found in response",
            )
          end

          message_payload = {
            "parts" => JSON.parse([{type: "text", text: prompt}].to_json),
          } of String => JSON::Any

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

          CogniCore::Workflow::AgentResult.new(
            agent_type: "function",
            content: content,
            metadata: {
              "engine" => JSON.parse("opencode".to_json),
              "session_id" => JSON.parse(session_id.to_json),
              "base_url" => JSON.parse(base_url.to_json),
            } of String => JSON::Any,
          )
        rescue ex
          CogniCore::Workflow::AgentResult.new(
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

      private def parse_openai_chat_content(body : String) : String?
        parsed = JSON.parse(body).as_h?
        return nil unless parsed
        choices = parsed["choices"]?.try(&.as_a?)
        return nil unless choices && !choices.empty?
        first = choices[0].as_h?
        return nil unless first
        message = first["message"]?.try(&.as_h?)
        return nil unless message
        if content = message["content"]?.try(&.as_s?)
          return content
        end
        parts = message["content"]?.try(&.as_a?)
        return nil unless parts
        parts.compact_map { |part| part.as_h?.try(&.["text"]?).try(&.as_s?) }.join("\n")
      rescue
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
    end
  end
end
