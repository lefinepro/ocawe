require "json"
require "http/client"
require "uri"
require "set"
require "../config/settings"
require "../workflows/declarative/types"
require "../workflows/declarative/node"

module Cogni
  module MCP
    alias AnyHash = Cogni::Workflows::Declarative::AnyHash

    class Manager
      @servers = {} of String => Cogni::Config::MCPServerSettings
      @dynamic_ids = Set(String).new
      @static_ids = Set(String).new
      @tool_catalog = {} of String => Array(AnyHash)
      @resource_catalog = {} of String => Array(AnyHash)
      @prompt_catalog = {} of String => Array(AnyHash)
      @status = {} of String => String
      @store_path = ".meta/mcp_servers.json"
      @http_path = "/mcp"
      @http_bearer_token = nil.as(String?)
      @lock = Mutex.new

      def configure(config : Cogni::Config::MCPSettings) : Nil
        @store_path = config.dynamic_store_path
        @http_path = config.http_server.path
        @http_bearer_token = config.http_server.bearer_token

        @lock.synchronize do
          @servers.clear
          @dynamic_ids.clear
          @static_ids.clear
          @tool_catalog.clear
          @resource_catalog.clear
          @prompt_catalog.clear
          @status.clear
        end

        config.servers.each do |server|
          next unless server.enabled
          set_server(server, dynamic: false)
        end

        load_dynamic_store
        refresh_all
      end

      def mcp_http_path : String
        @http_path
      end

      def mcp_http_bearer_token : String?
        @http_bearer_token
      end

      def list_servers : Array(AnyHash)
        @lock.synchronize do
          @servers.values.map do |server|
            source = @static_ids.includes?(server.id) ? "static" : "dynamic"
            {
              "id" => json_any(server.id),
              "transport" => json_any(server.transport),
              "command" => json_any(server.command || ""),
              "args" => json_any(server.args),
              "url" => json_any(server.url || ""),
              "enabled" => json_any(server.enabled),
              "source" => json_any(source),
              "status" => json_any(@status[server.id]? || "unknown"),
            } of String => JSON::Any
          end
        end
      end

      def get_server(server_id : String) : AnyHash?
        @lock.synchronize do
          server = @servers[server_id]?
          next nil unless server
          source = @static_ids.includes?(server.id) ? "static" : "dynamic"
          {
            "id" => json_any(server.id),
            "transport" => json_any(server.transport),
            "command" => json_any(server.command || ""),
            "args" => json_any(server.args),
            "env" => json_any(server.env),
            "url" => json_any(server.url || ""),
            "enabled" => json_any(server.enabled),
            "source" => json_any(source),
            "status" => json_any(@status[server.id]? || "unknown"),
          } of String => JSON::Any
        end
      end

      def create_dynamic(server : Cogni::Config::MCPServerSettings) : AnyHash
        @lock.synchronize do
          raise "server already exists: #{server.id}" if @servers.has_key?(server.id)
          @servers[server.id] = server
          @dynamic_ids.add(server.id)
          @status[server.id] = "configured"
        end
        persist_dynamic_store
        refresh(server.id)
        get_server(server.id) || raise "server not found after create: #{server.id}"
      end

      def update_dynamic(server_id : String, server : Cogni::Config::MCPServerSettings) : AnyHash
        @lock.synchronize do
          raise "cannot modify static server: #{server_id}" if @static_ids.includes?(server_id)
          raise "server not found: #{server_id}" unless @servers.has_key?(server_id)
          @servers.delete(server_id)
          @dynamic_ids.delete(server_id)
          @servers[server.id] = server
          @dynamic_ids.add(server.id)
          @status[server.id] = "configured"
        end
        persist_dynamic_store
        refresh(server.id)
        get_server(server.id) || raise "server not found after update: #{server.id}"
      end

      def delete_dynamic(server_id : String) : Bool
        deleted = false
        @lock.synchronize do
          raise "cannot delete static server: #{server_id}" if @static_ids.includes?(server_id)
          deleted = !!@servers.delete(server_id)
          @dynamic_ids.delete(server_id)
          @tool_catalog.delete(server_id)
          @resource_catalog.delete(server_id)
          @prompt_catalog.delete(server_id)
          @status.delete(server_id)
        end
        persist_dynamic_store if deleted
        deleted
      end

      def reconnect(server_id : String) : AnyHash
        refresh(server_id)
        get_server(server_id) || raise "server not found: #{server_id}"
      end

      def catalog : AnyHash
        {
          "tools" => json_any(list_tools),
          "resources" => json_any(list_resources),
          "prompts" => json_any(list_prompts),
        } of String => JSON::Any
      end

      def list_tools : Array(AnyHash)
        @lock.synchronize do
          result = [] of AnyHash
          @tool_catalog.each do |server_id, items|
            items.each do |item|
              result << item_with_canonical(server_id, item)
            end
          end
          result
        end
      end

      def list_resources : Array(AnyHash)
        @lock.synchronize do
          result = [] of AnyHash
          @resource_catalog.each do |server_id, items|
            items.each do |item|
              result << item_with_canonical(server_id, item)
            end
          end
          result
        end
      end

      def list_prompts : Array(AnyHash)
        @lock.synchronize do
          result = [] of AnyHash
          @prompt_catalog.each do |server_id, items|
            items.each do |item|
              result << item_with_canonical(server_id, item)
            end
          end
          result
        end
      end

      def call_tool(server_id : String, tool_name : String, arguments : AnyHash = {} of String => JSON::Any) : AnyHash
        server = find_server(server_id)
        params = {
          "name" => json_any(tool_name),
          "arguments" => json_any(arguments),
        } of String => JSON::Any
        result = rpc_call(server, "tools/call", params)
        data = result.as_h?.try { |h| h["content"]?.try(&.as_h?) }
        data || (result.as_h? || {"result" => json_any(result.raw)} of String => JSON::Any)
      end

      def read_resource(server_id : String, resource_name : String, arguments : AnyHash = {} of String => JSON::Any) : AnyHash
        server = find_server(server_id)
        params = {
          "name" => json_any(resource_name),
          "arguments" => json_any(arguments),
        } of String => JSON::Any
        result = rpc_call(server, "resources/read", params)
        result.as_h? || {"result" => json_any(result.raw)} of String => JSON::Any
      end

      def get_prompt(server_id : String, prompt_name : String, arguments : AnyHash = {} of String => JSON::Any) : AnyHash
        server = find_server(server_id)
        params = {
          "name" => json_any(prompt_name),
          "arguments" => json_any(arguments),
        } of String => JSON::Any
        result = rpc_call(server, "prompts/get", params)
        result.as_h? || {"result" => json_any(result.raw)} of String => JSON::Any
      end

      private def set_server(server : Cogni::Config::MCPServerSettings, dynamic : Bool) : Nil
        @lock.synchronize do
          @servers[server.id] = server
          if dynamic
            @dynamic_ids.add(server.id)
          else
            @static_ids.add(server.id)
          end
          @status[server.id] = "configured"
        end
      end

      private def find_server(server_id : String) : Cogni::Config::MCPServerSettings
        @lock.synchronize do
          @servers[server_id]? || raise "unknown mcp server: #{server_id}"
        end
      end

      private def refresh_all : Nil
        ids = @lock.synchronize { @servers.keys.dup }
        ids.each { |id| refresh(id) }
      end

      private def refresh(server_id : String) : Nil
        server = find_server(server_id)
        begin
          tools_result = rpc_call(server, "tools/list")
          resources_result = rpc_call(server, "resources/list")
          prompts_result = rpc_call(server, "prompts/list")

          tool_items = tools_result.as_h?.try { |h| h["tools"]?.try(&.as_a?) } || [] of JSON::Any
          resource_items = resources_result.as_h?.try { |h| h["resources"]?.try(&.as_a?) } || [] of JSON::Any
          prompt_items = prompts_result.as_h?.try { |h| h["prompts"]?.try(&.as_a?) } || [] of JSON::Any

          @lock.synchronize do
            @tool_catalog[server_id] = tool_items.map { |x| x.as_h? || {} of String => JSON::Any }
            @resource_catalog[server_id] = resource_items.map { |x| x.as_h? || {} of String => JSON::Any }
            @prompt_catalog[server_id] = prompt_items.map { |x| x.as_h? || {} of String => JSON::Any }
            @status[server_id] = "ready"
          end
        rescue ex
          @lock.synchronize do
            @tool_catalog[server_id] = [] of AnyHash
            @resource_catalog[server_id] = [] of AnyHash
            @prompt_catalog[server_id] = [] of AnyHash
            @status[server_id] = "error: #{ex.message}"
          end
        end
      end

      private def item_with_canonical(server_id : String, item : AnyHash) : AnyHash
        name = item["name"]?.try(&.as_s?) || item["id"]?.try(&.as_s?) || "unknown"
        out = item.dup
        out["server_id"] = json_any(server_id)
        out["canonical_id"] = json_any("mcp:#{server_id}:#{name}")
        out
      end

      private def rpc_call(server : Cogni::Config::MCPServerSettings, method : String, params : AnyHash? = nil) : JSON::Any
        payload_h = {
          "jsonrpc" => json_any("2.0"),
          "id" => json_any(Random::Secure.hex(8)),
          "method" => json_any(method),
        } of String => JSON::Any
        payload_h["params"] = json_any(params) if params
        payload = payload_h.to_json

        if server.transport == "stdio"
          call_stdio(server, payload)
        else
          call_http(server, payload)
        end
      end

      private def call_http(server : Cogni::Config::MCPServerSettings, payload : String) : JSON::Any
        url = server.url || raise "mcp http server url missing for #{server.id}"
        headers = HTTP::Headers{"Content-Type" => "application/json"}
        if token = server.bearer_token
          headers["Authorization"] = "Bearer #{token}"
        end
        response = HTTP::Client.post(url, body: payload, headers: headers)
        raise "mcp http #{server.id} status #{response.status_code}" unless response.success?
        parse_rpc_response(response.body)
      end

      private def call_stdio(server : Cogni::Config::MCPServerSettings, payload : String) : JSON::Any
        command = server.command || raise "mcp stdio command missing for #{server.id}"
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        input = IO::Memory.new("#{payload}\n")

        status = Process.run(command, args: server.args, input: input, output: stdout, error: stderr, env: server.env)
        unless status.success?
          raise "mcp stdio #{server.id} exited #{status.exit_code}: #{stderr.to_s.strip}"
        end
        parse_rpc_response(stdout.to_s)
      end

      private def parse_rpc_response(raw : String) : JSON::Any
        parsed = JSON.parse(raw)
        if error = parsed["error"]?
          message = error.as_h?.try { |h| h["message"]?.try(&.as_s?) } || "mcp rpc error"
          raise message
        end
        parsed["result"]? || JSON.parse("null")
      rescue ex : JSON::ParseException
        raise "invalid mcp rpc response: #{ex.message}"
      end

      private def persist_dynamic_store : Nil
        list = @lock.synchronize do
          @dynamic_ids.compact_map { |id| @servers[id]? }
        end
        dir = File.dirname(@store_path)
        Dir.mkdir_p(dir) unless Dir.exists?(dir)
        File.write(@store_path, list.to_json)
      rescue
      end

      private def load_dynamic_store : Nil
        return unless File.exists?(@store_path)
        parsed = JSON.parse(File.read(@store_path)).as_a?
        return unless parsed

        parsed.each do |item|
          next unless hash = item.as_h?
          server = parse_server(hash)
          next if @lock.synchronize { @static_ids.includes?(server.id) }
          set_server(server, dynamic: true)
        end
      rescue
      end

      private def parse_server(body : AnyHash) : Cogni::Config::MCPServerSettings
        id = body["id"]?.try(&.as_s?) || raise "server id required"
        transport = body["transport"]?.try(&.as_s?) || "http"
        command = body["command"]?.try(&.as_s?)
        args = body["args"]?.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String
        env = {} of String => String
        body["env"]?.try(&.as_h?).try(&.each { |k, v| env[k] = v.as_s? || v.raw.to_s })
        url = body["url"]?.try(&.as_s?)
        bearer_token = body["bearer_token"]?.try(&.as_s?)
        enabled = body["enabled"]?.try(&.as_bool?) != false
        Cogni::Config::MCPServerSettings.new(
          id: id,
          transport: transport,
          command: command,
          args: args,
          env: env,
          url: url,
          bearer_token: bearer_token,
          enabled: enabled,
        )
      end

      private def json_any(value) : JSON::Any
        JSON.parse(value.to_json)
      end
    end

    @@manager = Manager.new

    def self.manager : Manager
      @@manager
    end

    def self.parse_mcp_ref(ref : String) : {String, String}
      body = ref.sub(/^mcp:/, "")
      first = body.index(':')
      raise "invalid mcp reference: #{ref}" unless first
      server = body[0, first]
      name = body[first + 1, body.bytesize - first - 1]
      raise "invalid mcp reference: #{ref}" if server.empty? || name.empty?
      {server, name}
    end
  end
end
