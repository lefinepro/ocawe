module CogniCore
  module Workflow
    alias FunctionHandler = Proc(NodeContext, AgentResult)

    class FunctionRegistry
      def initialize
        @functions = {} of String => FunctionHandler
      end

      def register(name : String, &block : NodeContext -> AgentResult)
        @functions[normalize(name)] = block
      end

      def call(name : String, ctx : NodeContext) : AgentResult
        key = normalize(name)
        handler = @functions[key]?
        raise "unknown function: #{name}" unless handler
        handler.call(ctx)
      end

      def registered?(name : String) : Bool
        @functions.has_key?(normalize(name))
      end

      private def normalize(value : String) : String
        value.strip.downcase
      end
    end

    @@function_registry = FunctionRegistry.new

    def self.function_registry : FunctionRegistry
      @@function_registry
    end

    def self.register_function(name : String, &block : NodeContext -> AgentResult)
      @@function_registry.register(name, &block)
    end
  end
end
