require "./types"
require "process"
require "json"

module ACP
  # ACP Client for stdio transport
  # Manages communication with an ACP agent over stdin/stdout
  class Client
    getter agent_info : AgentInfo?
    getter agent_capabilities : AgentCapabilities?
    getter session_id : String?

    @process : Process?
    @request_id : Int32
    @pending_responses : Hash(Int32, Channel(JsonRpcResponse))
    @notification_channel : Channel(JsonRpcNotification)
    @reader_fiber : Fiber?
    @closed : Bool

    def initialize(@command : String, @args : Array(String) = [] of String, @env : Hash(String, String) = {} of String => String)
      @request_id = 0
      @pending_responses = {} of Int32 => Channel(JsonRpcResponse)
      @notification_channel = Channel(JsonRpcNotification).new(100)
      @agent_info = nil
      @agent_capabilities = nil
      @session_id = nil
      @closed = false
    end

    # Start the agent process and initialize the connection
    def start : InitializeResult
      raise "Client already started" if @process

      @process = Process.new(
        @command,
        args: @args,
        env: @env,
        input: Process::Redirect::Pipe,
        output: Process::Redirect::Pipe,
        error: Process::Redirect::Pipe
      )

      # Start reader fiber
      @reader_fiber = spawn do
        read_loop
      end

      # Send initialize request
      params_json = {
        "protocolVersion" => 1,
        "clientCapabilities" => {
          "fs" => {
            "readTextFile" => true,
            "writeTextFile" => true
          },
          "terminal" => true
        },
        "clientInfo" => {
          "name" => "ocawe",
          "title" => "Ocawe Runtime",
          "version" => "0.0.1"
        }
      }

      params = InitializeParams.from_json(params_json.to_json)

      result = request("initialize", params)
      init_result = InitializeResult.from_json(result.to_json)

      @agent_info = init_result.agentInfo
      @agent_capabilities = init_result.agentCapabilities

      init_result
    end

    # Create a new session
    def create_session(cwd : String, mcp_servers : Array(JSON::Any) = [] of JSON::Any) : String
      params_json = {
        "cwd" => cwd,
        "mcpServers" => mcp_servers.empty? ? nil : mcp_servers,
        "additionalDirectories" => nil
      }.compact

      params = SessionNewParams.from_json(params_json.to_json)

      result = request("session/new", params)
      session_result = SessionNewResult.from_json(result.to_json)
      @session_id = session_result.sessionId
      session_result.sessionId
    end

    # Send a prompt to the agent
    def prompt(prompt_text : String, session_id : String? = nil) : SessionPromptResult
      sid = session_id || @session_id || raise "No active session"

      params_json = {
        "sessionId" => sid,
        "prompt" => [{
          "type" => "text",
          "text" => prompt_text
        }]
      }

      params = SessionPromptParams.from_json(params_json.to_json)

      result = request("session/prompt", params)
      SessionPromptResult.from_json(result.to_json)
    end

    # Send a prompt with content blocks
    def prompt_with_content(content : Array(ContentBlock), session_id : String? = nil) : SessionPromptResult
      sid = session_id || @session_id || raise "No active session"

      params_json = {
        "sessionId" => sid,
        "prompt" => content.map(&.to_json)
      }

      params = SessionPromptParams.from_json(params_json.to_json)

      result = request("session/prompt", params)
      SessionPromptResult.from_json(result.to_json)
    end

    # Cancel the current session operation
    def cancel(session_id : String? = nil)
      sid = session_id || @session_id || raise "No active session"

      params_json = {"sessionId" => sid}
      params = SessionCancelParams.from_json(params_json.to_json)
      send_notification("session/cancel", params)
    end

    # Get next session update notification (blocking)
    def next_update(timeout : Time::Span? = nil) : SessionUpdate?
      if timeout
        select
        when notification = @notification_channel.receive
          return parse_session_update(notification) if notification.method == "session/update"
        when timeout(timeout)
          return nil
        end
      else
        notification = @notification_channel.receive
        return parse_session_update(notification) if notification.method == "session/update"
      end
      nil
    end

    # Collect all session updates until prompt completes
    def collect_updates : Array(SessionUpdate)
      updates = [] of SessionUpdate
      loop do
        update = next_update(timeout: 5.seconds)
        break unless update
        updates << update
      end
      updates
    end

    # Close the connection and terminate the agent process
    def close
      return if @closed
      @closed = true

      if proc = @process
        proc.input.close rescue nil
        proc.wait rescue nil
        @process = nil
      end

      @pending_responses.each_value(&.close)
      @pending_responses.clear
      @notification_channel.close
    end

    private def request(method : String, params : JSON::Serializable) : JSON::Any
      raise "Client not started" unless @process
      raise "Client closed" if @closed

      id = @request_id += 1
      req_json = {
        "jsonrpc" => "2.0",
        "id" => id,
        "method" => method,
        "params" => JSON.parse(params.to_json)
      }

      response_channel = Channel(JsonRpcResponse).new(1)
      @pending_responses[id] = response_channel

      send_message_json(req_json)

      response = response_channel.receive
      @pending_responses.delete(id)

      if error = response.error
        raise ProtocolError.new(error.message, error.code, error.data)
      end

      response.result || JSON.parse("{}")
    end

    private def send_notification(method : String, params : JSON::Serializable)
      raise "Client not started" unless @process
      raise "Client closed" if @closed

      notif_json = {
        "jsonrpc" => "2.0",
        "method" => method,
        "params" => JSON.parse(params.to_json)
      }

      send_message_json(notif_json)
    end

    private def send_message_json(message : Hash)
      proc = @process || raise "Client not started"
      line = message.to_json + "\n"
      proc.input << line
      proc.input.flush
    end

    private def send_message(message : JSON::Serializable)
      proc = @process || raise "Client not started"
      line = message.to_json + "\n"
      proc.input << line
      proc.input.flush
    end

    private def read_loop
      proc = @process || return

      while !@closed
        begin
          line = proc.output.gets
          break unless line

          handle_message(line)
        rescue ex
          STDERR.puts "ACP client read error: #{ex.message}"
          break
        end
      end
    rescue ex
      STDERR.puts "ACP client read loop error: #{ex.message}"
    end

    private def handle_message(line : String)
      json = JSON.parse(line)

      if json["id"]?
        # Response
        response = JsonRpcResponse.from_json(line)
        if id = response.id
          if id.is_a?(Int64)
            id = id.to_i32
          elsif id.is_a?(String)
            id = id.to_i32? || return
          end

          if channel = @pending_responses[id]?
            channel.send(response)
          end
        end
      else
        # Notification
        notification = JsonRpcNotification.from_json(line)
        @notification_channel.send(notification)
      end
    rescue ex
      STDERR.puts "ACP client message parse error: #{ex.message}"
    end

    private def parse_session_update(notification : JsonRpcNotification) : SessionUpdate?
      return nil unless notification.params
      SessionUpdate.from_json(notification.params.to_json)
    rescue
      nil
    end
  end
end
