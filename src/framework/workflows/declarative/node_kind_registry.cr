module Ocawe
  module Workflow
      alias NodeKindResult = WorkflowNodeResult | AnyHash
      alias NodeKindHandler = Proc(NodeContext, AnyHash, NodeKindResult)

      class NodeKindRegistry
        def initialize
          @handlers = {} of String => NodeKindHandler
        end

        def reset! : Nil
          @handlers.clear
        end

        def register(kind : String, &block : NodeContext, AnyHash -> NodeKindResult) : Nil
          key = normalize(kind)
          raise "invalid node kind: #{kind}" if key.empty?
          raise "node kind already registered: #{kind}" if @handlers.has_key?(key)
          @handlers[key] = block
        end

        def call(kind : String, ctx : NodeContext, parameters : AnyHash) : NodeKindResult
          key = normalize(kind)
          handler = @handlers[key]?
          return handler.call(ctx, parameters) if handler

          # Backward-compatible fallback: treat bare workflow calls
          # (`function_name`) as function-registry handlers when there
          # is no explicit node kind registered.
          if Ocawe::Workflow.function_registry.registered?(kind)
            return Ocawe::Workflow.function_registry.call(kind, ctx)
          end

          raise "unknown node kind: #{kind}"
        end

        private def normalize(kind : String) : String
          kind.strip.downcase
        end
      end

      @@node_kind_registry = NodeKindRegistry.new

      def self.node_kind_registry : NodeKindRegistry
        @@node_kind_registry
      end

      def self.reset_node_kind_registry! : Nil
        @@node_kind_registry.reset!
      end

      def self.register_node_kind(kind : String, &block : NodeContext, AnyHash -> NodeKindResult) : Nil
        @@node_kind_registry.register(kind, &block)
      end
    end
end
