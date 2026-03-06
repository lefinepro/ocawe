# RCL AST Nodes
# Abstract Syntax Tree for RCL configuration

require "json"

module RCL
  # Base AST node
  abstract class ASTNode
    abstract def kind : String
    abstract def to_ast_h : Hash(String, RCL::Value)
    abstract def to_json(json : JSON::Builder) : Nil
  end

  # String value node
  class StringNode < ASTNode
    getter value : String
    def initialize(@value); end

    def kind : String
      "string"
    end

    def to_ast_h : Hash(String, RCL::Value)
      {
        "kind"  => kind,
        "value" => @value,
      }
    end

    def to_json(json : JSON::Builder) : Nil
      to_ast_h.to_json(json)
    end
  end

  # Number value node (Int32, Int64, or Float64)
  class NumberNode < ASTNode
    getter value : Int32 | Int64 | Float64
    def initialize(@value); end

    def kind : String
      "number"
    end

    def to_ast_h : Hash(String, RCL::Value)
      {
        "kind"  => kind,
        "value" => @value,
      }
    end

    def to_json(json : JSON::Builder) : Nil
      to_ast_h.to_json(json)
    end
  end

  # Boolean value node
  class BooleanNode < ASTNode
    getter value : Bool
    def initialize(@value); end

    def kind : String
      "boolean"
    end

    def to_ast_h : Hash(String, RCL::Value)
      {
        "kind"  => kind,
        "value" => @value,
      }
    end

    def to_json(json : JSON::Builder) : Nil
      to_ast_h.to_json(json)
    end
  end

  # Array of values
  class ArrayNode < ASTNode
    getter elements : Array(ASTNode)
    def initialize(@elements); end

    def kind : String
      "array"
    end

    def to_ast_h : Hash(String, RCL::Value)
      {
        "kind"     => kind,
        "elements" => @elements.map(&.to_ast_h),
      }
    end

    def to_json(json : JSON::Builder) : Nil
      to_ast_h.to_json(json)
    end
  end

  # Block/section with nested properties and blocks
  class BlockNode < ASTNode
    getter name : String
    getter argument : String?
    getter properties : Hash(String, ASTNode)
    getter blocks : Hash(String, BlockNode)
    getter named_blocks : Array(BlockNode)

    def initialize(
      @name,
      @argument : String? = nil,
      @properties = {} of String => ASTNode,
      @blocks = {} of String => BlockNode,
      @named_blocks = [] of BlockNode
    )
    end

    def kind : String
      "block"
    end

    # Get property or block by key
    def []?(key : String) : ASTNode?
      @properties[key]? || @blocks[key]?
    end

    # Set property
    def []=(key : String, value : ASTNode)
      @properties[key] = value
    end

    # Check if has key
    def has_key?(key : String) : Bool
      @properties.has_key?(key) || @blocks.has_key?(key)
    end

    # Get all keys
    def keys : Array(String)
      @properties.keys | @blocks.keys
    end

    def to_ast_h : Hash(String, RCL::Value)
      properties = {} of String => RCL::Value
      @properties.each do |key, value|
        properties[key] = value.to_ast_h
      end

      blocks = {} of String => RCL::Value
      @blocks.each do |key, value|
        blocks[key] = value.to_ast_h
      end

      data = {
        "kind"       => kind,
        "name"       => @name,
        "properties" => properties,
        "blocks"     => blocks,
      } of String => RCL::Value
      data["argument"] = @argument.not_nil! if @argument
      data["named_blocks"] = @named_blocks.map(&.to_ast_h) unless @named_blocks.empty?
      data
    end

    def to_json(json : JSON::Builder) : Nil
      to_ast_h.to_json(json)
    end
  end

  # Type alias for RCL values
  alias Value = String | Int32 | Int64 | Float64 | Bool | Array(Value) | Hash(String, Value)
end
