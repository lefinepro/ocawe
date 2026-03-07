module ACD
  module Kemal
    class App
      private def mount_mcp_endpoints
        get "/v1/mcp/servers" do |env|
          env.response.content_type = "application/json"
          {"servers" => @mcp_manager.list_servers}.to_json
        end

        post "/v1/mcp/servers" do |env|
          body = json_body(env)
          created = with_workflow_errors(env) do
            @mcp_manager.create_dynamic(parse_mcp_server_settings(body))
          end
          next created if created.is_a?(String)

          env.response.status_code = 201
          env.response.content_type = "application/json"
          created.to_json
        end

        get "/v1/mcp/servers/:serverId" do |env|
          server_id = env.params.url["serverId"]
          server = @mcp_manager.get_server(server_id)
          unless server
            env.response.status_code = 404
            env.response.content_type = "application/json"
            next({error: {type: "not_found", message: "mcp server not found: #{server_id}"}}.to_json)
          end

          env.response.content_type = "application/json"
          server.to_json
        end

        patch "/v1/mcp/servers/:serverId" do |env|
          server_id = env.params.url["serverId"]
          body = json_body(env)
          updated = with_workflow_errors(env) do
            @mcp_manager.update_dynamic(server_id, parse_mcp_server_settings(body, fallback_id: server_id))
          end
          next updated if updated.is_a?(String)
          env.response.content_type = "application/json"
          updated.to_json
        end

        delete "/v1/mcp/servers/:serverId" do |env|
          server_id = env.params.url["serverId"]
          removed = with_workflow_errors(env) do
            @mcp_manager.delete_dynamic(server_id)
          end
          next removed if removed.is_a?(String)
          unless removed.as(Bool)
            env.response.status_code = 404
            env.response.content_type = "application/json"
            next({error: {type: "not_found", message: "mcp server not found: #{server_id}"}}.to_json)
          end
          env.response.status_code = 204
          ""
        end

        post "/v1/mcp/servers/:serverId/reconnect" do |env|
          server_id = env.params.url["serverId"]
          response = with_workflow_errors(env) do
            @mcp_manager.reconnect(server_id)
          end
          next response if response.is_a?(String)
          env.response.content_type = "application/json"
          response.to_json
        end

        get "/v1/mcp/catalog" do |env|
          env.response.content_type = "application/json"
          @mcp_manager.catalog.to_json
        end

        get "/v1/mcp/catalog/tools" do |env|
          env.response.content_type = "application/json"
          {"tools" => @mcp_manager.list_tools}.to_json
        end

        get "/v1/mcp/catalog/resources" do |env|
          env.response.content_type = "application/json"
          {"resources" => @mcp_manager.list_resources}.to_json
        end

        get "/v1/mcp/catalog/prompts" do |env|
          env.response.content_type = "application/json"
          {"prompts" => @mcp_manager.list_prompts}.to_json
        end
      end

      private def mount_mcp_server_endpoint
        post @mcp_manager.mcp_http_path do |env|
          if configured_token = @mcp_manager.mcp_http_bearer_token
            auth_header = env.request.headers["Authorization"]?
            expected = "Bearer #{configured_token}"
            if auth_header != expected
              env.response.status_code = 401
              env.response.content_type = "application/json"
              next({error: {type: "auth_error", message: "unauthorized"}}.to_json)
            end
          end

          body = json_body(env)
          id = body["id"]? || JSON.parse("null")
          method = body["method"]?.try(&.as_s?) || ""
          params = body["params"]?.try(&.as_h?) || {} of String => JSON::Any

          response = with_workflow_errors(env) do
            dispatch_mcp_rpc(method, params)
          end

          if response.is_a?(String)
            env.response.content_type = "application/json"
            next({
              "jsonrpc" => "2.0",
              "id" => id,
              "error" => {"code" => -32000, "message" => "rpc failed"},
            }.to_json)
          end

          env.response.content_type = "application/json"
          {
            "jsonrpc" => "2.0",
            "id" => id,
            "result" => response,
          }.to_json
        end
      end

      private def dispatch_mcp_rpc(method : String, params : Cogni::Workflow::AnyHash) : Cogni::Workflow::AnyHash
        case method
        when "initialize"
          {
            "protocolVersion" => JSON.parse("2025-06-18".to_json),
            "capabilities" => JSON.parse({
              "tools" => {"listChanged" => true},
              "resources" => {"listChanged" => true},
              "prompts" => {"listChanged" => true},
            }.to_json),
            "serverInfo" => JSON.parse({"name" => "cogni", "version" => CogniCore::VERSION}.to_json),
          } of String => JSON::Any
        when "ping"
          {} of String => JSON::Any
        when "tools/list"
          {
            "tools" => JSON.parse(mcp_server_tools.to_json),
          } of String => JSON::Any
        when "tools/call"
          handle_mcp_tools_call(params)
        when "resources/list"
          local_resources = Cogni::Workflow.resource_registry.names.map do |name|
            {
              "name" => JSON.parse(name.to_json),
              "description" => JSON.parse("Cogni resource #{name}".to_json),
            } of String => JSON::Any
          end
          {
            "resources" => JSON.parse((local_resources + @mcp_manager.list_resources).to_json),
          } of String => JSON::Any
        when "resources/read"
          handle_mcp_resources_read(params)
        when "prompts/list"
          local_prompts = agents.map do |agent|
            {
              "name" => JSON.parse("agent:#{agent[:id]}".to_json),
              "description" => JSON.parse("Prompt for agent #{agent[:id]}".to_json),
            } of String => JSON::Any
          end
          {
            "prompts" => JSON.parse((local_prompts + @mcp_manager.list_prompts).to_json),
          } of String => JSON::Any
        when "prompts/get"
          handle_mcp_prompts_get(params)
        else
          raise "unsupported mcp method: #{method}"
        end
      end

      private def mcp_server_tools : Array(Cogni::Workflow::AnyHash)
        local = tools.map do |tool|
          {
            "name" => JSON.parse(tool[:id].to_json),
            "description" => JSON.parse("Cogni tool #{tool[:id]}".to_json),
          } of String => JSON::Any
        end
        local + @mcp_manager.list_tools
      end

      private def handle_mcp_tools_call(params : Cogni::Workflow::AnyHash) : Cogni::Workflow::AnyHash
        name = params["name"]?.try(&.as_s?) || raise "tools/call requires name"
        arguments = params["arguments"]?.try(&.as_h?) || {} of String => JSON::Any

        if name.starts_with?("mcp:")
          server_id, tool_name = Cogni::MCP.parse_mcp_ref(name)
          return {
            "content" => JSON.parse(@mcp_manager.call_tool(server_id, tool_name, arguments).to_json),
          } of String => JSON::Any
        end

        ctx = Cogni::Workflow::NodeContext.new(
          workflow_id: "mcp",
          run_id: "mcp",
          node_id: name,
          input_data: arguments,
          state: arguments,
        )
        {
          "content" => JSON.parse(Cogni::RegistryApi.call_function(name, ctx).to_json),
        } of String => JSON::Any
      end

      private def handle_mcp_resources_read(params : Cogni::Workflow::AnyHash) : Cogni::Workflow::AnyHash
        name = params["name"]?.try(&.as_s?) || raise "resources/read requires name"
        arguments = params["arguments"]?.try(&.as_h?) || {} of String => JSON::Any

        if name.starts_with?("mcp:")
          server_id, resource_name = Cogni::MCP.parse_mcp_ref(name)
          return @mcp_manager.read_resource(server_id, resource_name, arguments)
        end

        ctx = Cogni::Workflow::NodeContext.new(
          workflow_id: "mcp",
          run_id: "mcp",
          node_id: name,
          input_data: arguments,
          state: arguments,
        )
        Cogni::Workflow.resource_registry.call(name, ctx, arguments)
      end

      private def handle_mcp_prompts_get(params : Cogni::Workflow::AnyHash) : Cogni::Workflow::AnyHash
        name = params["name"]?.try(&.as_s?) || raise "prompts/get requires name"
        arguments = params["arguments"]?.try(&.as_h?) || {} of String => JSON::Any

        if name.starts_with?("mcp:")
          server_id, prompt_name = Cogni::MCP.parse_mcp_ref(name)
          return @mcp_manager.get_prompt(server_id, prompt_name, arguments)
        end

        if name.starts_with?("agent:")
          agent_id = name.sub(/^agent:/, "")
          if agent = agent_by_id(agent_id)
            return {
              "name" => JSON.parse(name.to_json),
              "content" => JSON.parse(agent[:prompt].to_json),
            } of String => JSON::Any
          end
        end

        raise "prompt not found: #{name}"
      end

      private def parse_mcp_server_settings(body : Cogni::Workflow::AnyHash, fallback_id : String? = nil) : Cogni::Config::MCPServerSettings
        id = body["id"]?.try(&.as_s?) || fallback_id || raise "mcp server id is required"
        transport = body["transport"]?.try(&.as_s?) || "http"
        command = body["command"]?.try(&.as_s?)
        args = body["args"]?.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String
        env = {} of String => String
        body["env"]?.try(&.as_h?).try(&.each do |k, v|
          env[k] = v.as_s? || v.raw.to_s
        end)
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
    end
  end
end
