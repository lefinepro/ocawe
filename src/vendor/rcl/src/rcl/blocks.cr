# RCL Block Handlers Registry
# Allows registering custom handlers for specific block types
#
# Usage:
#   RCL::Blocks.register("server") do |block, config|
#     config.server_address = block["address"]
#   end

module RCL
  module Blocks
    # Result type for block processing
    struct Result
      property status : Symbol
      property block : BlockNode?
      
      def initialize(@status : Symbol, @block : BlockNode?)
      end
    end

    # Handler type: receives BlockNode and returns processed result
    alias Handler = BlockNode -> Result

    # Registry of block handlers
    @@handlers = {} of String => Handler

    # Register a handler for a block type
    def self.register(name : String, &block : BlockNode -> Result)
      @@handlers[name] = block
    end

    # Check if handler exists for block type
    def self.registered?(name : String) : Bool
      @@handlers.has_key?(name)
    end

    # Get handler for block type
    def self.handler(name : String) : Handler?
      @@handlers[name]?
    end

    # Process a block with registered handler
    def self.process(block : BlockNode) : Result
      handler = @@handlers[block.name]?
      if handler
        handler.call(block)
      else
        # Unknown block - return as-is
        Result.new(:unknown, block)
      end
    end

    # Process all blocks from document
    def self.process_document(doc : Document) : Array(Result)
      results = [] of Result
      doc.blocks.each do |block|
        results << process(block)
      end
      results
    end

    # Clear all handlers (for testing)
    def self.clear
      @@handlers.clear
    end

    # Get all registered handler names
    def self.names : Array(String)
      @@handlers.keys.to_a
    end
  end
end
