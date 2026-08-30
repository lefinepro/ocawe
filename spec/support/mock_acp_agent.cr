# Mock ACP agent - responds to initialize, session/new, session/prompt
# Usage: crystal run mock_acp_agent.cr

require "json"

STDOUT.sync = true
STDIN.sync = true

message_id = 0

def handle_request(req)
  id = req["id"]
  method = req["method"]
  params = req["params"] || {} of String => JSON::Any

  case method
  when "initialize"
    {
      "jsonrpc" => "2.0",
      "id"      => id,
      "result"  => {
        "protocolVersion"   => 1,
        "agentCapabilities" => {
          "loadSession"        => false,
          "promptCapabilities" => {
            "image"           => false,
            "audio"           => false,
            "embeddedContext" => false,
          },
        },
        "agentInfo" => {
          "name"    => "mock-acp",
          "title"   => "Mock ACP Agent",
          "version" => "1.0.0",
        },
        "authMethods" => [] of String,
      },
    }
  when "session/new"
    {
      "jsonrpc" => "2.0",
      "id"      => id,
      "result"  => {
        "sessionId" => "sess_mock_12345",
        "models" => [{"id" => "gpt-5.4", "name" => "GPT-5.4"}],
      },
    }
  when "session/set_model"
    {
      "jsonrpc" => "2.0",
      "id"      => id,
      "result"  => {"modelId" => params["modelId"]},
    }
  when "session/prompt"
    session_id = params["sessionId"]
    prompt = params["prompt"]
    prompt_text = ""
    prompt.as_a.each do |block|
      if block["type"]?.try(&.as_s?) == "text"
        prompt_text = block["text"]?.try(&.as_s?) || ""
      end
    end

    if ENV["MOCK_ACP_REQUEST_PERMISSION"]? == "1"
      puts({
        "jsonrpc" => "2.0",
        "id"      => 900,
        "method"  => "session/request_permission",
        "params"  => {
          "sessionId" => session_id,
          "toolCall"  => {"toolCallId" => "mock-tool"},
          "options"   => [
            {"optionId" => "allow-once", "name" => "Allow once", "kind" => "allow_once"},
            {"optionId" => "reject-once", "name" => "Reject", "kind" => "reject_once"},
          ],
        },
      }.to_json)
      STDOUT.flush
      permission_line = STDIN.gets || raise "permission response missing"
      permission = JSON.parse(permission_line)
      selected = permission["result"]["outcome"]["optionId"]?.try(&.as_s?)
      raise "permission was not allowed once" unless selected == "allow-once"
    end

    chunks = if ENV["MOCK_ACP_CHUNKS"]? == "many"
               (1..12).map { |index| "chunk-#{index}" }
             else
               ["Mock ACP agent received: #{prompt_text}"]
             end
    chunks.each_with_index do |chunk, index|
      puts({
        "jsonrpc" => "2.0",
        "method"  => "session/update",
        "params"  => {
          "sessionId" => session_id,
          "update"    => {
            "sessionUpdate" => "agent_message_chunk",
            "messageId"     => "msg_agent_#{index}",
            "content"       => {
              "type" => "text",
              "text" => chunk,
            },
          },
        },
      }.to_json)
    end

    # Send final response
    {
      "jsonrpc" => "2.0",
      "id"      => id,
      "result"  => {
        "stopReason" => "end_turn",
      },
    }
  when "session/cancel"
    {
      "jsonrpc" => "2.0",
      "method"  => "session/cancel",
      "params"  => {} of String => JSON::Any,
    }
  else
    {
      "jsonrpc" => "2.0",
      "id"      => id,
      "error"   => {
        "code"    => -32601,
        "message" => "Method not found: #{method}",
      },
    }
  end
end

loop do
  line = STDIN.gets
  break unless line
  line = line.chomp
  next if line.empty?

  req = JSON.parse(line)
  begin
    resp = handle_request(req)
    puts resp.to_json
    STDOUT.flush
  rescue ex
    puts({
      "jsonrpc" => "2.0",
      "id"      => req["id"],
      "error"   => {
        "code"    => -32700,
        "message" => ex.message,
      },
    }.to_json)
    STDOUT.flush
  end
end
