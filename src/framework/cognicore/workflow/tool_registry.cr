module CogniCore
  module Workflow
    alias ToolFunction = Proc(NodeContext, AnyHash)

    class ToolRegistry
      def initialize
        @tools = {} of String => ToolFunction
      end

      def register(name : String, &block : NodeContext -> AnyHash)
        @tools[normalize(name)] = block
      end

      def call(tool_id : String, ctx : NodeContext, function_name : String? = nil) : AnyHash
        function_key = normalize(function_name || default_function_name(tool_id))
        function = @tools[function_key]?
        raise "unknown tool function: #{function_key} (tool: #{tool_id})" unless function
        function.call(ctx)
      end

      def default_function_name(tool_id : String) : String
        normalize_identifier(tool_id)
      end

      private def normalize(value : String) : String
        value.strip.downcase
      end

      private def normalize_identifier(value : String) : String
        normalized = value.downcase.gsub(/[^a-z0-9]+/, "_")
        normalized = normalized.gsub(/_+/, "_")
        normalized = normalized.gsub(/^_+|_+$/, "")
        raise "invalid tool id: #{value}" if normalized.empty?
        normalized
      end
    end

    @@tool_registry = ToolRegistry.new

    def self.tool_registry : ToolRegistry
      @@tool_registry
    end

    def self.register_tool(name : String, &block : NodeContext -> AnyHash)
      @@tool_registry.register(name, &block)
    end
  end
end
