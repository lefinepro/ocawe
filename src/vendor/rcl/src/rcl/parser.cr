require "./lexer"
require "./ast"
require "./parser_helpers"
require "set"

module RCL
  class Parser
    include ParserHelpers

    getter lexer : Lexer
    getter current_token : Token

    def initialize(@lexer)
      @current_token = @lexer.next_token
    end

    def self.parse(content : String) : Document
      lexer = RCL::Lexer.new(content)
      new(lexer).parse
    end

    def parse : Document
      if @current_token.type == TokenType::Do
        eat(TokenType::Do)
        root_array = parse_array
        raise "Unexpected token after root array at line #{@current_token.line}, column #{@current_token.column}" unless @current_token.type == TokenType::EOF
        return Document.new([] of BlockNode, root_value: root_array)
      end

      properties = {} of String => ASTNode
      blocks = [] of BlockNode
      root_blocks = {} of String => BlockNode
      named_blocks = [] of BlockNode
      seen_keys = Set(String).new

      while @current_token.type != TokenType::EOF
        raise "Expected identifier at line #{@current_token.line}, column #{@current_token.column}" unless @current_token.type == TokenType::Identifier

        next_token = peek_token
        if next_token.type == TokenType::Do
          after_do = peek_token(2)
          if after_do.type == TokenType::LBracket
            key = @current_token.value
            eat(TokenType::Identifier)
            ensure_property_key_valid!(key, seen_keys)
            eat(TokenType::Do)
            properties[key] = parse_array
            eat(TokenType::End)
          else
            child = parse_block
            if child.argument
              named_blocks << child
            else
              blocks << child
              root_blocks[child.name] = child
            end
          end
        elsif next_token.type == TokenType::String
          child = parse_block
          if child.argument
            named_blocks << child
          else
            blocks << child
            root_blocks[child.name] = child
          end
        elsif next_token.type == TokenType::Equal || next_token.type == TokenType::Dot
          key = parse_property_key
          ensure_property_key_valid!(key, seen_keys)
          eat(TokenType::Equal)
          properties[key] = parse_value
        else
          raise "invalid statement after '#{@current_token.value}' at line #{@current_token.line}, column #{@current_token.column}"
        end
      end

      return Document.new(blocks) if properties.empty? && named_blocks.empty?
      root_block = BlockNode.new("__root__", nil, properties, root_blocks, named_blocks)
      Document.new([] of BlockNode, root_value: root_block)
    end

    private def parse_block : BlockNode
      name = @current_token.value
      eat(TokenType::Identifier)

      argument : String? = nil
      if @current_token.type == TokenType::String
        argument = @current_token.value
        eat(TokenType::String)
      end

      eat(TokenType::Do)

      properties, blocks, named_blocks = parse_block_body

      eat(TokenType::End)
      BlockNode.new(name, argument, properties, blocks, named_blocks)
    end

    private def parse_anonymous_block : BlockNode
      eat(TokenType::Do)
      properties, blocks, named_blocks = parse_block_body
      eat(TokenType::End)
      BlockNode.new("", nil, properties, blocks, named_blocks)
    end

    private def parse_block_body
      properties = {} of String => ASTNode
      blocks = {} of String => BlockNode
      named_blocks = [] of BlockNode
      seen_keys = Set(String).new

      while @current_token.type != TokenType::End
        if @current_token.type == TokenType::EOF
          raise "missing 'end' for block at line #{@current_token.line}, column #{@current_token.column}"
        end
        raise "Expected identifier at line #{@current_token.line}, column #{@current_token.column}" unless @current_token.type == TokenType::Identifier

        next_token = peek_token
        if next_token.type == TokenType::Do
          after_do = peek_token(2)
          if after_do.type == TokenType::LBracket
            key = @current_token.value
            eat(TokenType::Identifier)
            ensure_property_key_valid!(key, seen_keys)
            eat(TokenType::Do)
            properties[key] = parse_array
            eat(TokenType::End)
          else
            child = parse_block
            if child.argument
              named_blocks << child
            else
              blocks[child.name] = child
            end
          end
        elsif next_token.type == TokenType::String
          child = parse_block
          if child.argument
            named_blocks << child
          else
            blocks[child.name] = child
          end
        elsif next_token.type == TokenType::Equal || next_token.type == TokenType::Dot
          key = parse_property_key
          ensure_property_key_valid!(key, seen_keys)
          eat(TokenType::Equal)
          properties[key] = parse_value
        else
          raise "invalid statement after '#{@current_token.value}' at line #{@current_token.line}, column #{@current_token.column}"
        end
      end

      {properties, blocks, named_blocks}
    end

    private def parse_property_key : String
      key = @current_token.value
      eat(TokenType::Identifier)

      while @current_token.type == TokenType::Dot
        eat(TokenType::Dot)
        raise "Expected identifier after dot at line #{@current_token.line}, column #{@current_token.column}" unless @current_token.type == TokenType::Identifier
        key += "." + @current_token.value
        eat(TokenType::Identifier)
      end

      key
    end

    private def parse_value : ASTNode
      case @current_token.type
      when TokenType::String
        value = @current_token.value
        eat(TokenType::String)
        StringNode.new(value)
      when TokenType::Number
        value = parse_number(@current_token.value)
        eat(TokenType::Number)
        NumberNode.new(value)
      when TokenType::Identifier
        value = @current_token.value
        eat(TokenType::Identifier)
        if value == "true"
          BooleanNode.new(true)
        elsif value == "false"
          BooleanNode.new(false)
        else
          raise "Invalid bare value '#{value}' at line #{@current_token.line}, column #{@current_token.column}"
        end
      when TokenType::LBracket
        parse_array
      when TokenType::Do
        parse_anonymous_block
      else
        raise "Unexpected token: #{@current_token.type} at line #{@current_token.line}"
      end
    end

    private def parse_array : ArrayNode
      eat(TokenType::LBracket)
      elements = [] of ASTNode

      while @current_token.type != TokenType::RBracket
        elements << parse_value
        if @current_token.type == TokenType::Comma
          eat(TokenType::Comma)
          if @current_token.type == TokenType::RBracket
            raise "Trailing comma in array at line #{@current_token.line}, column #{@current_token.column}"
          end
        end
      end

      eat(TokenType::RBracket)
      ArrayNode.new(elements)
    end

  end
end
