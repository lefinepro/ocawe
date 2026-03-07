require "./ast"
require "./document_helpers"
require "json"
require "set"

module RCL
  class Document
    include DocumentHelpers

    getter blocks : Array(BlockNode)
    getter root : Hash(String, ASTNode)
    getter root_value : ASTNode?

    def initialize(@blocks = [] of BlockNode, @root_value : ASTNode? = nil)
      @root = {} of String => ASTNode

      if @root_value
        @root = {} of String => ASTNode
      elsif @blocks.size == 1
        block = @blocks.first
        block.properties.each { |k, v| @root[k] = v }
        block.blocks.each { |k, v| @root[k] = v }
      else
        @blocks.each do |block|
          @root[block.name] = block
        end
      end
    end

    def []?(key : String) : ASTNode?
      @root[key]?
    end

    def get(path : String) : ASTNode?
      parts = path.split('.')
      current : ASTNode? = @root[parts[0]]?

      if rest = parts[1..-1]?
        rest.each do |part|
          break unless current.is_a?(BlockNode)
          current = current.as(BlockNode)[part]?
        end
      end

      current
    end

    def get_string(path : String, default : String? = nil) : String?
      node = get(path)
      node.is_a?(StringNode) ? node.as(StringNode).value : default
    end

    def get_int(path : String, default : Int32? = nil) : Int32?
      node = get(path)
      if node.is_a?(NumberNode)
        value = node.as(NumberNode).value
        value.is_a?(Int32) || value.is_a?(Int64) ? value.to_i : default
      else
        default
      end
    end

    def get_float(path : String, default : Float64? = nil) : Float64?
      node = get(path)
      node.is_a?(NumberNode) ? node.as(NumberNode).value.to_f : default
    end

    def get_bool(path : String, default : Bool? = nil) : Bool?
      node = get(path)
      node.is_a?(BooleanNode) ? node.as(BooleanNode).value : default
    end

    def get_array(path : String) : ArrayNode?
      node = get(path)
      node.is_a?(ArrayNode) ? node.as(ArrayNode) : nil
    end

    def block(name : String) : BlockNode?
      @root[name]?.as(BlockNode?)
    end

    def has_key?(path : String) : Bool
      get(path).nil? == false
    end

    def to_h : Hash(String, RCL::Value)
      if rv = @root_value
        return {"root" => node_to_h(rv)} of String => RCL::Value
      end

      result = {} of String => RCL::Value
      @blocks.each do |block|
        if arg = block.argument
          result[named_base(block.name)] = {arg => block_to_h(block)} of String => RCL::Value
        else
          result[block.name] = block_to_h(block)
        end
      end

      result
    end

    def to_value : RCL::Value
      if rv = @root_value
        node_to_h(rv)
      else
        to_h
      end
    end

    def to_ast_h : Hash(String, RCL::Value)
      if rv = @root_value
        {
          "kind"  => "document",
          "value" => rv.to_ast_h,
        }
      else
        {
          "kind"   => "document",
          "blocks" => @blocks.map(&.to_ast_h),
        }
      end
    end

    def to_json(json : JSON::Builder) : Nil
      to_ast_h.to_json(json)
    end

    private def block_to_h(block : BlockNode) : Hash(String, RCL::Value)
      result = {} of String => RCL::Value

      block.properties.each do |key, node|
        insert_key_path!(result, key, node_to_h(node))
      end

      children = unique_child_blocks(block)

      plain_children = children.select { |child| child.argument.nil? }
      named_children = children.select { |child| !child.argument.nil? }

      plain_children.each do |child|
        child_h = block_to_h(child)
        existing = result[child.name]?
        if existing.is_a?(Hash(String, RCL::Value))
          merged = child_h.dup
          existing.each do |k, v|
            merged[k] = v
          end
          result[child.name] = merged
        else result[child.name] = child_h
        end
      end

      named_children.each do |child|
        base = named_base(child.name)
        arg = child.argument.not_nil!
        branch = result[base]?
        branch_h = branch.is_a?(Hash(String, RCL::Value)) ? branch : ({} of String => RCL::Value)
        branch_h[arg] = block_to_h(child)
        result[base] = branch_h
      end

      result
    end

    private def node_to_h(node : ASTNode) : RCL::Value
      case node
      when StringNode
        node.value
      when NumberNode
        node.value
      when BooleanNode
        node.value
      when ArrayNode
        node.elements.map { |e| node_to_h(e) }
      when BlockNode
        block_to_h(node)
      else
        ""
      end
    end

  end
end
