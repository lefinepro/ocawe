require "./types"

module Ocawe
  module Workflows
    module DSL
    module CrystalDSL
      class ParseError < Exception
      end

      def self.compile(source : String, context : String = "schema") : Validator
        parser = Parser.new(source.strip, context)
        parser.parse
      end

      private class Parser
        def initialize(@source : String, @context : String)
          @index = 0
        end

        def parse : Validator
          validator = parse_validator
          skip_ws
          raise error("unexpected trailing content") unless eof?
          validator
        end

        private def parse_validator : Validator
          expect("Schema::Types.")
          name = parse_identifier
          expect("(")
          case name
          when "any"
            expect(")")
            Types.any
          when "of"
            type_name = parse_identifier
            expect(")")
            parse_of(type_name)
          when "optional"
            inner = parse_validator
            expect(")")
            Types.optional(inner)
          when "array"
            inner = parse_validator
            expect(")")
            Types.array(inner)
          when "enum"
            values = parse_string_array
            expect(")")
            Types.enum(values)
          when "object"
            fields = parse_object_fields
            strict = true
            skip_ws
            if consume(",")
              skip_ws
              key = parse_identifier
              raise error("expected strict keyword") unless key == "strict"
              skip_ws
              expect(":")
              strict = parse_bool
            end
            expect(")")
            Types.object(fields, strict: strict)
          else
            raise error("unsupported Schema::Types method '#{name}'")
          end
        end

        private def parse_of(type_name : String) : Validator
          case type_name
          when "String"
            Types.of(String)
          when "Int32"
            Types.of(Int32)
          when "Int64"
            Types.of(Int64)
          when "Float64"
            Types.of(Float64)
          when "Bool"
            Types.of(Bool)
          when "Hash"
            Types.of(Hash)
          when "Array"
            Types.of(Array)
          else
            raise error("unsupported type '#{type_name}' in Schema::Types.of")
          end
        end

        private def parse_object_fields : Hash(String, Validator)
          skip_ws
          expect("{")
          fields = {} of String => Validator

          skip_ws
          until consume("}")
            key = parse_string
            skip_ws
            expect("=>")
            skip_ws
            value = parse_validator
            fields[key] = value
            skip_ws
            break if consume("}")
            expect(",")
            skip_ws
          end

          fields
        end

        private def parse_string_array : Array(String)
          skip_ws
          expect("[")
          values = [] of String
          skip_ws
          until consume("]")
            values << parse_string
            skip_ws
            break if consume("]")
            expect(",")
            skip_ws
          end
          values
        end

        private def parse_identifier : String
          skip_ws
          start = @index
          while !eof? && identifier_char?(char_at(@index))
            @index += 1
          end
          raise error("expected identifier") if @index == start
          @source[start...@index]
        end

        private def parse_bool : Bool
          skip_ws
          if consume("true")
            true
          elsif consume("false")
            false
          else
            raise error("expected boolean")
          end
        end

        private def parse_string : String
          skip_ws
          raise error("expected string") if eof?
          quote = char_at(@index)
          raise error("expected string") unless quote == '"'
          @index += 1

          terminated = false
          value = String.build do |io|
            while !eof?
              ch = char_at(@index)
              @index += 1
              if ch == '\\'
                raise error("unterminated string escape") if eof?
                escaped = char_at(@index)
                @index += 1
                case escaped
                when '"', '\\'
                  io << escaped
                when 'n'
                  io << '\n'
                when 't'
                  io << '\t'
                else
                  io << escaped
                end
                next
              end
              if ch == '"'
                terminated = true
                break
              end
              io << ch
            end
          end

          raise error("unterminated string") unless terminated
          value
        end

        private def skip_ws
          while !eof?
            ch = char_at(@index)
            break unless ch.whitespace?
            @index += 1
          end
        end

        private def expect(token : String)
          skip_ws
          raise error("expected '#{token}'") unless consume(token)
        end

        private def consume(token : String) : Bool
          return false if @index + token.size > @source.size
          return false unless @source[@index, token.size] == token
          @index += token.size
          true
        end

        private def char_at(index : Int32) : Char
          @source[index]
        end

        private def eof? : Bool
          @index >= @source.size
        end

        private def identifier_char?(ch : Char) : Bool
          ch.alphanumeric? || ch == '_'
        end

        private def error(message : String) : ParseError
          ParseError.new("#{@context}: #{message} at offset #{@index}")
        end
      end
    end
  end
  end
end
