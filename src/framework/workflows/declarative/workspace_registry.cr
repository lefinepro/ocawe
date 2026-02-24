module Cogni
  module Workflow
    class WorkspaceRegistry
      alias SchemaHandler = AnyHash -> Nil
      alias ResolverHandler = AnyHash -> AnyHash
      alias HookHandler = NodeContext, AnyHash -> Nil

      def initialize
        @schema_handlers = {} of String => SchemaHandler
        @resolver_handlers = [] of ResolverHandler
        @hooks = {} of String => Array(HookHandler)
      end

      def reset! : Nil
        @schema_handlers.clear
        @resolver_handlers.clear
        @hooks.clear
      end

      def register_schema(name : String, &block : AnyHash -> Nil) : Nil
        @schema_handlers[name] = block
      end

      def register_resolver(&block : AnyHash -> AnyHash) : Nil
        @resolver_handlers << block
      end

      def register_hook(event : String, &block : NodeContext, AnyHash -> Nil) : Nil
        handlers = (@hooks[event]? || [] of HookHandler)
        handlers << block
        @hooks[event] = handlers
      end

      def resolve(config : AnyHash) : AnyHash
        normalized = normalize(config)
        @schema_handlers.each_value { |handler| handler.call(normalized) }
        @resolver_handlers.each do |handler|
          normalized = normalize(handler.call(normalized))
        end
        normalized
      end

      def emit(event : String, ctx : NodeContext, workspace : AnyHash) : Nil
        handlers = @hooks[event]?
        return unless handlers
        payload = normalize(workspace)
        handlers.each { |handler| handler.call(ctx, payload) }
      end

      private def normalize(hash : AnyHash) : AnyHash
        JSON.parse(hash.to_json).as_h
      end
    end

    @@workspace_registry = WorkspaceRegistry.new

    def self.workspace_registry : WorkspaceRegistry
      @@workspace_registry
    end

    def self.reset_workspace_registry! : Nil
      @@workspace_registry.reset!
    end
  end
end
