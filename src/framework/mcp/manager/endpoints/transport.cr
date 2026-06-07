module Ocawe
  module MCP
    class Manager
      private def set_server(server : Ocawe::Config::MCPServerSettings, dynamic : Bool) : Nil
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

      private def find_server(server_id : String) : Ocawe::Config::MCPServerSettings
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

      private def rpc_call(server : Ocawe::Config::MCPServerSettings, method : String, params : AnyHash? = nil) : JSON::Any
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

      private def call_http(server : Ocawe::Config::MCPServerSettings, payload : String) : JSON::Any
        url = server.url || raise "mcp http server url missing for #{server.id}"
        headers = HTTP::Headers{"Content-Type" => "application/json"}
        if token = server.bearer_token
          headers["Authorization"] = "Bearer #{token}"
        end
        response = HTTP::Client.post(url, body: payload, headers: headers)
        raise "mcp http #{server.id} status #{response.status_code}" unless response.success?
        parse_rpc_response(response.body)
      end

      private def call_stdio(server : Ocawe::Config::MCPServerSettings, payload : String) : JSON::Any
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
    end
  end
end
