require "../../mcp/manager"

module Ocawe
  module Workflow
      alias ResourceHandler = Proc(NodeContext, AnyHash, AnyHash)

      class ResourceRegistry
        def initialize
          @handlers = {} of String => ResourceHandler
        end

        def reset! : Nil
          @handlers.clear
        end

        def register(name : String, &block : NodeContext, AnyHash -> AnyHash) : Nil
          key = normalize(name)
          raise "invalid resource name: #{name}" if key.empty?
          raise "resource handler already registered: #{name}" if @handlers.has_key?(key)
          @handlers[key] = block
        end

        def call(name : String, ctx : NodeContext, payload : AnyHash = {} of String => JSON::Any) : AnyHash
          key = normalize(name)
          if key.starts_with?("mcp:")
            server_id, resource_name = Ocawe::MCP.parse_mcp_ref(name)
            return Ocawe::MCP.manager.read_resource(server_id, resource_name, payload)
          end
          handler = @handlers[key]?
          raise "unknown resource handler: #{name}" unless handler
          handler.call(ctx, payload)
        end

        def names : Array(String)
          @handlers.keys.sort
        end

        private def normalize(name : String) : String
          name.strip.downcase
        end
      end

      @@resource_registry = ResourceRegistry.new

      def self.resource_registry : ResourceRegistry
        @@resource_registry
      end

      def self.reset_resource_registry! : Nil
        @@resource_registry.reset!
      end

      def self.register_resource(name : String, &block : NodeContext, AnyHash -> AnyHash) : Nil
        @@resource_registry.register(name, &block)
      end
    end
end
