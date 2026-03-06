# RCL Formatter
# Formats AST back into canonical RCL source text

require "./document"
require "set"

module RCL
  class Formatter
    def self.format(document : Document) : String
      new.format(document)
    end

    def format(document : Document) : String
      if rv = document.root_value
        return "do #{format_value(rv)}" if rv.is_a?(ArrayNode)
      end
      document.blocks.map { |block| format_block(block, 0) }.join("\n\n")
    end

    private def format_block(block : BlockNode, indent : Int32) : String
      lines = [] of String
      pad = "  " * indent
      header = block.argument ? "#{pad}#{block.name} #{quote(block.argument.not_nil!)} do" : "#{pad}#{block.name} do"
      lines << header

      block.properties.each do |key, value|
        if value.is_a?(ArrayNode)
          lines << "#{pad}  #{key} do #{format_value(value)} end"
        else
          lines << "#{pad}  #{key} = #{format_value(value)}"
        end
      end

      each_child_block(block) do |child|
        lines << format_block(child, indent + 1)
      end

      lines << "#{pad}end"
      lines.join("\n")
    end

    private def each_child_block(block : BlockNode, & : BlockNode ->)
      seen = Set(UInt64).new
      block.blocks.each_value do |child|
        oid = child.object_id
        next if seen.includes?(oid)
        seen << oid
        yield child
      end
      block.named_blocks.each do |child|
        oid = child.object_id
        next if seen.includes?(oid)
        seen << oid
        yield child
      end
    end

    private def format_value(node : ASTNode) : String
      case node
      when StringNode
        quote(node.value)
      when NumberNode
        node.value.to_s
      when BooleanNode
        node.value ? "true" : "false"
      when ArrayNode
        "[#{node.elements.map { |element| format_value(element) }.join(", ")}]"
      when BlockNode
        format_anonymous_block(node)
      else
        raise "Unsupported AST node for formatter: #{node.class}"
      end
    end

    private def format_anonymous_block(block : BlockNode) : String
      parts = [] of String
      block.properties.each do |k, v|
        parts << "#{k} = #{format_value(v)}"
      end
      each_child_block(block) do |child|
        parts << format_block_inline(child)
      end
      body = parts.join(" ")
      body.empty? ? "do end" : "do #{body} end"
    end

    private def format_block_inline(block : BlockNode) : String
      header = block.argument ? "#{block.name} #{quote(block.argument.not_nil!)} do" : "#{block.name} do"
      parts = [] of String
      block.properties.each do |k, v|
        parts << "#{k} = #{format_value(v)}"
      end
      each_child_block(block) do |child|
        parts << format_block_inline(child)
      end
      body = parts.join(" ")
      body.empty? ? "#{header} end" : "#{header} #{body} end"
    end

    private def quote(value : String) : String
      escaped = value.gsub("\\", "\\\\").gsub("\"", "\\\"").gsub("\n", "\\n").gsub("\t", "\\t")
      "\"#{escaped}\""
    end
  end
end
