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
      "id" => id,
      "result" => {
        "protocolVersion" => 1,
        "agentCapabilities" => {
          "loadSession" => false,
          "promptCapabilities" => {
            "image" => false,
            "audio" => false,
            "embeddedContext" => false
          }
        },
        "agentInfo" => {
          "name" => "mock-acp",
          "title" => "Mock ACP Agent",
          "version" => "1.0.0"
        },
        "authMethods" => [] of String
      }
    }
  when "session/new"
    {
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => {
        "sessionId" => "sess_mock_12345"
      }
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

    # Send session/update notification first
    update = {
      "jsonrpc" => "2.0",
      "method" => "session/update",
      "params" => {
        "sessionId" => session_id,
        "update" => {
          "sessionUpdate" => "agent_message_chunk",
          "messageId" => "msg_agent_001",
          "content" => {
            "type" => "text",
            "text" => "Mock ACP agent received: #{prompt_text}"
          }
        }
      }
    }
    puts update.to_json

    # Send final response
    {
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => {
        "stopReason" => "end_turn"
      }
    }
  when "session/cancel"
    {
      "jsonrpc" => "2.0",
      "method" => "session/cancel",
      "params" => {} of String => JSON::Any
    }
  else
    {
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => {
        "code" => -32601,
        "message" => "Method not found: #{method}"
      }
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
      "id" => req["id"],
      "error" => {
        "code" => -32700,
        "message" => ex.message
      }
    }.to_json)
    STDOUT.flush
  end
end
