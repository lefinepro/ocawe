module Ocawe
  module MCP
    class Manager
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
    end
  end
end
