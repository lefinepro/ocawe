# Mock ACP agent that exercises client-side filesystem requests.

require "json"

STDOUT.sync = true
STDIN.sync = true

request_id = 1000
session_id = "sess_fs_mock"

def rpc_response(id, result)
  {
    "jsonrpc" => "2.0",
    "id"      => id,
    "result"  => result,
  }
end

def rpc_error(id, code, message)
  {
    "jsonrpc" => "2.0",
    "id"      => id,
    "error"   => {
      "code"    => code,
      "message" => message,
    },
  }
end

def client_request(method, params, request_id)
  puts({
    "jsonrpc" => "2.0",
    "id"      => request_id,
    "method"  => method,
    "params"  => params,
  }.to_json)
  STDOUT.flush
  response_line = STDIN.gets || raise "client closed before #{method} response"
  JSON.parse(response_line)
end

loop do
  line = STDIN.gets
  break unless line
  next if line.strip.empty?

  req = JSON.parse(line)
  id = req["id"]
  method = req["method"].as_s

  case method
  when "initialize"
    puts rpc_response(id, {
      "protocolVersion"    => 1,
      "agentCapabilities"  => {"loadSession" => false},
      "agentInfo"          => {"name" => "fs-mock", "version" => "1.0.0"},
      "authMethods"        => [] of String,
    }).to_json
  when "session/new"
    puts rpc_response(id, {"sessionId" => session_id}).to_json
  when "session/prompt"
    mode = ENV["ACP_FS_MODE"]? || "write-read"
    path = ENV["ACP_FS_PATH"]? || "nested/sentinel.txt"
    content = ENV["ACP_FS_CONTENT"]? || "sentinel"
    request_id += 1

    fs_result = case mode
                when "write-read"
                  write_response = client_request("fs/writeTextFile", {"path" => path, "content" => content}, request_id)
                  request_id += 1
                  read_response = client_request("fs/readTextFile", {"path" => path}, request_id)
                  if error = write_response["error"]?
                    "write error: #{error["message"]?}"
                  elsif error = read_response["error"]?
                    "read error: #{error["message"]?}"
                  else
                    read_response["result"]["content"].as_s
                  end
                when "write-only"
                  write_response = client_request("fs/writeTextFile", {"path" => path, "content" => content}, request_id)
                  if error = write_response["error"]?
                    "write error: #{error["message"]?}"
                  else
                    "write ok"
                  end
                when "read-only"
                  read_response = client_request("fs/readTextFile", {"path" => path}, request_id)
                  if error = read_response["error"]?
                    "read error: #{error["message"]?}"
                  else
                    read_response["result"]["content"].as_s
                  end
                else
                  "unknown mode: #{mode}"
                end

    puts({
      "jsonrpc" => "2.0",
      "method"  => "session/update",
      "params"  => {
        "sessionId" => session_id,
        "update"    => {
          "sessionUpdate" => "agent_message_chunk",
          "messageId"     => "msg_fs_mock",
          "content"       => {"type" => "text", "text" => fs_result},
        },
      },
    }.to_json)
    puts rpc_response(id, {"stopReason" => "end_turn"}).to_json
  else
    puts rpc_error(id, -32601, "Method not found: #{method}").to_json
  end
  STDOUT.flush
end
