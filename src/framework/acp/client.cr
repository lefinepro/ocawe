require "./types"
require "process"
require "json"

module ACP
  # ACP Client for stdio transport
  # Manages communication with an ACP agent over stdin/stdout
  class Client
    class FilesystemPolicy
      getter root : String
      getter write_policy : String

      def initialize(root : String, @write_policy : String = "write")
        @root = File.expand_path(root)
      end

      def writable? : Bool
        @write_policy != "read_only"
      end

      def resolve(path : String) : String
        candidate = path.starts_with?("/") ? File.expand_path(path) : File.expand_path(path, @root)
        unless candidate == @root || candidate.starts_with?(@root + File::SEPARATOR)
          raise ProtocolError.new("path escapes workspace", ErrorCode::INVALID_PARAMS, JSON.parse({"path" => path, "root" => @root}.to_json))
        end
        candidate
      end
    end

    getter agent_info : AgentInfo?
    getter agent_capabilities : AgentCapabilities?
    getter session_id : String?
    getter session_models : JSON::Any?
    getter session_config_options : JSON::Any?

    @process : Process?
    @request_id : Int32
    @pending_responses : Hash(Int32, Channel(JsonRpcResponse))
    @notification_channel : Channel(JsonRpcNotification)
    @reader_fiber : Fiber?
    @stderr_reader_fiber : Fiber?
    @closed : Bool

    def initialize(
      @command : String,
      @args : Array(String) = [] of String,
      @env : Hash(String, String) = {} of String => String,
      @filesystem_policy : FilesystemPolicy? = nil,
      @process_cwd : String? = nil,
    )
      @request_id = 0
      @pending_responses = {} of Int32 => Channel(JsonRpcResponse)
      @notification_channel = Channel(JsonRpcNotification).new(10000)
      @agent_info = nil
      @agent_capabilities = nil
      @session_id = nil
      @session_models = nil
      @session_config_options = nil
      @closed = false
      @stderr_reader_fiber = nil
    end

    # Start the agent process and initialize the connection
    def start : InitializeResult
      raise "Client already started" if @process

      @process = Process.new(
        @command,
        args: @args,
        env: @env,
        chdir: @process_cwd,
        input: Process::Redirect::Pipe,
        output: Process::Redirect::Pipe,
        error: Process::Redirect::Pipe
      )

      # Start reader fiber
      @reader_fiber = spawn do
        read_loop
      end

      # ACP agents may emit large diagnostics to stderr (for example while
      # refreshing their model cache). Leaving the pipe unread eventually
      # blocks the child process and makes the JSON-RPC request wait forever.
      @stderr_reader_fiber = spawn do
        drain_stderr
      end

      # Send initialize request
      params_json = {
        "protocolVersion"    => 1,
        "clientCapabilities" => {
          "fs" => {
            "readTextFile"  => true,
            "writeTextFile" => true,
          },
          "terminal" => true,
        },
        "clientInfo" => {
          "name"    => "ocawe",
          "title"   => "Ocawe Runtime",
          "version" => "0.0.1",
        },
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
      params_json = {"cwd" => JSON.parse(cwd.to_json)} of String => JSON::Any
      params_json["mcpServers"] = JSON.parse(mcp_servers.to_json)

      params = JSON.parse(params_json.to_json)

      result = request("session/new", params)
      session_result = SessionNewResult.from_json(result.to_json)
      @session_id = session_result.sessionId
      @session_models = session_result.models
      @session_config_options = session_result.configOptions
      session_result.sessionId
    end

    # Codex ACP versions expose model selection either through the dedicated
    # method or through the generic session configuration method.
    def set_model(model_id : String, session_id : String? = nil) : JSON::Any
      sid = session_id || @session_id || raise "No active session"
      model = model_id.strip
      raise "Model id is empty" if model.empty?

      begin
        return request("session/set_model", JSON.parse({
          "sessionId" => sid,
          "modelId"   => model,
        }.to_json))
      rescue ex : ProtocolError
        unless ex.code == ErrorCode::METHOD_NOT_FOUND || ex.code == ErrorCode::INVALID_PARAMS
          raise ex
        end
      end

      request("session/set_config_option", JSON.parse({
        "sessionId" => sid,
        "configId"  => "model",
        "value"     => model,
      }.to_json))
    end

    # Send a prompt to the agent
    def prompt(prompt_text : String, session_id : String? = nil) : SessionPromptResult
      sid = session_id || @session_id || raise "No active session"

      params_json = {
        "sessionId" => sid,
        "prompt"    => [{
          "type" => "text",
          "text" => prompt_text,
        }],
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
        "prompt"    => content.map(&.to_json),
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

    # A prompt response is written after all of its preceding update
    # notifications on the same stdio stream. Drain every update already
    # queued when the response arrives without adding a fixed post-response
    # delay or an arbitrary chunk limit.
    def drain_updates : Array(SessionUpdate)
      updates = [] of SessionUpdate
      loop do
        notification = select
        when value = @notification_channel.receive
          value
        else
          break
        end
        next unless notification.method == "session/update"
        if update = parse_session_update(notification)
          updates << update
        end
      end
      updates
    end

    # Close the connection and terminate the agent process
    def close
      return if @closed
      @closed = true

      if proc = @process
        proc.input.close rescue nil
        proc.terminate rescue nil
        spawn { proc.wait rescue nil }
        @process = nil
      end

      @pending_responses.each_value(&.close)
      @pending_responses.clear
      @notification_channel.close
    end

    private def request(method : String, params : JSON::Serializable | JSON::Any) : JSON::Any
      raise "Client not started" unless @process
      raise "Client closed" if @closed

      id = @request_id += 1
      req_json = {
        "jsonrpc" => "2.0",
        "id"      => id,
        "method"  => method,
        "params"  => JSON.parse(params.to_json),
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
        "method"  => method,
        "params"  => JSON.parse(params.to_json),
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

    private def drain_stderr
      proc = @process || return
      while proc.error.gets
      end
    rescue
      # stderr is diagnostic-only; a closed pipe must not affect ACP requests.
    end

    private def handle_message(line : String)
      json = JSON.parse(line)

      fields = json.as_h
      if fields.has_key?("id") && fields.has_key?("method")
        handle_request(json)
      elsif fields.has_key?("id")
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
        select
        when @notification_channel.send(notification)
        else
          STDERR.puts "ACP client notification dropped: channel full"
        end
      end
    rescue ex
      STDERR.puts "ACP client message parse error: #{ex.message}"
    end

    private def handle_request(json : JSON::Any) : Nil
      id = json["id"]
      method = json["method"].as_s
      params = json["params"]?
      result = dispatch_request(method, params)
      send_message_json({
        "jsonrpc" => "2.0",
        "id"      => id,
        "result"  => result,
      })
    rescue ex : ProtocolError
      send_error_response(json["id"]?, ex.code, ex.message || "ACP request failed", ex.data)
    rescue ex
      send_error_response(json["id"]?, ErrorCode::INTERNAL_ERROR, ex.message || ex.class.name)
    end

    private def dispatch_request(method : String, params : JSON::Any?) : JSON::Any
      case method
      when "fs/readTextFile"
        handle_read_text_file(params)
      when "fs/writeTextFile"
        handle_write_text_file(params)
      when "session/request_permission"
        handle_permission_request(params)
      else
        raise ProtocolError.new("Method not found: #{method}", ErrorCode::METHOD_NOT_FOUND)
      end
    end

    private def handle_read_text_file(params : JSON::Any?) : JSON::Any
      policy = @filesystem_policy || raise ProtocolError.new("filesystem access is not configured", ErrorCode::INVALID_REQUEST)
      path = extract_path_param(params)
      content = File.read(policy.resolve(path))
      JSON.parse({"content" => content}.to_json)
    rescue ex : File::NotFoundError
      raise ProtocolError.new("file not found", ErrorCode::INVALID_PARAMS, JSON.parse({"path" => extract_path_param(params)}.to_json))
    end

    private def handle_write_text_file(params : JSON::Any?) : JSON::Any
      policy = @filesystem_policy || raise ProtocolError.new("filesystem access is not configured", ErrorCode::INVALID_REQUEST)
      unless policy.writable?
        raise ProtocolError.new("workspace is read-only", ErrorCode::INVALID_REQUEST)
      end
      path = extract_path_param(params)
      content = extract_content_param(params)
      resolved = policy.resolve(path)
      parent = File.dirname(resolved)
      Dir.mkdir_p(parent) unless Dir.exists?(parent)
      File.write(resolved, content)
      JSON.parse({"path" => resolved}.to_json)
    end

    private def handle_permission_request(params : JSON::Any?) : JSON::Any
      values = params.try(&.as_h?) || raise ProtocolError.new("params must be an object", ErrorCode::INVALID_PARAMS)
      options = values["options"]?.try(&.as_a?) || raise ProtocolError.new("permission options are required", ErrorCode::INVALID_PARAMS)
      policy = ENV["OCAWE_ACP_PERMISSION_POLICY"]? || "allow_once"
      order = case policy.downcase
              when "deny", "reject"
                ["reject_once", "reject_always"]
              when "allow_always"
                ["allow_always", "allow_once"]
              else
                ["allow_once", "allow_always"]
              end
      selected = nil.as(JSON::Any?)
      order.each do |kind|
        selected = options.find { |option| option["kind"]?.try(&.as_s?) == kind }
        break if selected
      end
      selected ||= options.find { |option| option["kind"]?.try(&.as_s?).to_s.starts_with?("reject_") }
      return JSON.parse({"outcome" => {"outcome" => "cancelled"}}.to_json) unless selected

      option_id = selected["optionId"]?.try(&.as_s?) || raise ProtocolError.new("permission optionId is required", ErrorCode::INVALID_PARAMS)
      JSON.parse({
        "outcome" => {
          "outcome"  => "selected",
          "optionId" => option_id,
        },
      }.to_json)
    end

    private def extract_path_param(params : JSON::Any?) : String
      value = params.try(&.as_h?) || raise ProtocolError.new("params must be an object", ErrorCode::INVALID_PARAMS)
      path = value["path"]?.try(&.as_s?) || value["uri"]?.try(&.as_s?)
      raise ProtocolError.new("path is required", ErrorCode::INVALID_PARAMS) unless path
      path
    end

    private def extract_content_param(params : JSON::Any?) : String
      value = params.try(&.as_h?) || raise ProtocolError.new("params must be an object", ErrorCode::INVALID_PARAMS)
      content = value["content"]?.try(&.as_s?) || value["text"]?.try(&.as_s?)
      raise ProtocolError.new("content is required", ErrorCode::INVALID_PARAMS) unless content
      content
    end

    private def send_error_response(id : JSON::Any?, code : Int32, message : String, data : JSON::Any? = nil) : Nil
      error = {
        "code"    => JSON.parse(code.to_json),
        "message" => JSON.parse(message.to_json),
      } of String => JSON::Any
      error["data"] = data if data
      send_message_json({
        "jsonrpc" => "2.0",
        "id"      => id || JSON.parse("null"),
        "error"   => JSON.parse(error.to_json),
      })
    end

    private def parse_session_update(notification : JsonRpcNotification) : SessionUpdate?
      return nil unless notification.params
      SessionUpdate.from_json(notification.params.to_json)
    rescue
      nil
    end
  end
end
