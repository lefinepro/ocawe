require "set"

module RCL
  module ParserHelpers
    private def parse_number(value : String) : Int32 | Int64 | Float64
      if value.includes?('.')
        value.to_f
      elsif value.to_i64 > Int32::MAX || value.to_i64 < Int32::MIN
        value.to_i64
      else
        value.to_i
      end
    end

    private def eat(type : TokenType)
      if @current_token.type == type
        @current_token = @lexer.next_token
      else
        raise "Expected #{type}, got #{@current_token.type} at line #{@current_token.line}, column #{@current_token.column}"
      end
    end

    private def peek_token(offset : Int32 = 1) : Token
      saved_pos, saved_line, saved_col = @lexer.pos, @lexer.line, @lexer.column
      saved_token = @current_token

      token = @current_token
      offset.times do
        token = @lexer.next_token
      end

      @lexer.pos, @lexer.line, @lexer.column = saved_pos, saved_line, saved_col
      @current_token = saved_token

      token
    end

    private def ensure_property_key_valid!(key : String, seen : Set(String))
      if seen.includes?(key)
        raise "Duplicate key '#{key}' at line #{@current_token.line}, column #{@current_token.column}"
      end
      key_parts = key.split('.')
      seen.each do |existing|
        parts = existing.split('.')
        if prefix?(key_parts, parts) || prefix?(parts, key_parts)
          raise "Key conflict between '#{key}' and '#{existing}' at line #{@current_token.line}, column #{@current_token.column}"
        end
      end
      seen << key
    end

    private def prefix?(left : Array(String), right : Array(String)) : Bool
      return false if left.size >= right.size
      left.each_with_index do |part, idx|
        return false if right[idx] != part
      end
      true
    end
  end
end
