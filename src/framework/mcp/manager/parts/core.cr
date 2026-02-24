module Cogni
  module MCP
    alias AnyHash = Cogni::Workflow::AnyHash

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
    end
  end
end
