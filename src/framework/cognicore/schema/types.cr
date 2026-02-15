require "json"

module CogniCore
  module Schema
    class ValidationError < Exception
    end

    module Validator
      abstract def validate(value : JSON::Any, path : String = "$") : Nil
    end

    class AnyValidator
      include Validator

      def validate(value : JSON::Any, path : String = "$") : Nil
        _ = value
        _ = path
      end
    end

    class TypeValidator
      include Validator

      def initialize(@kind : Symbol)
      end

      def validate(value : JSON::Any, path : String = "$") : Nil
        raw = value.raw
        valid = case @kind
                when :string
                  raw.is_a?(String)
                when :int32
                  raw.is_a?(Int64)
                when :int64
                  raw.is_a?(Int64)
                when :float64
                  raw.is_a?(Float64) || raw.is_a?(Int64)
                when :bool
                  raw.is_a?(Bool)
                when :hash
                  raw.is_a?(Hash(String, JSON::Any))
                when :array
                  raw.is_a?(Array(JSON::Any))
                else
                  false
                end

        raise ValidationError.new("#{path} must be #{@kind}") unless valid
      end
    end

    class EnumValidator
      include Validator

      def initialize(@values : Array(String))
      end

      def validate(value : JSON::Any, path : String = "$") : Nil
        raw = value.raw
        raise ValidationError.new("#{path} must be string") unless raw.is_a?(String)
        raise ValidationError.new("#{path} must be one of #{@values.join(", ")}") unless @values.includes?(raw)
      end
    end

    class OptionalValidator
      include Validator

      def initialize(@inner : Validator)
      end

      def validate(value : JSON::Any, path : String = "$") : Nil
        return if value.raw.nil?
        @inner.validate(value, path)
      end
    end

    class ArrayValidator
      include Validator

      def initialize(@item : Validator)
      end

      def validate(value : JSON::Any, path : String = "$") : Nil
        arr = value.as_a?
        raise ValidationError.new("#{path} must be array") unless arr

        arr.each_with_index do |entry, index|
          @item.validate(entry, "#{path}[#{index}]")
        end
      end
    end

    class ObjectValidator
      include Validator

      def initialize(@fields : Hash(String, Validator), @strict : Bool = true)
      end

      def validate(value : JSON::Any, path : String = "$") : Nil
        source = value.as_h?
        raise ValidationError.new("#{path} must be object") unless source

        @fields.each do |key, validator|
          field = source[key]?
          if field
            validator.validate(field, "#{path}.#{key}")
          elsif !validator.is_a?(OptionalValidator)
            raise ValidationError.new("#{path}.#{key} is required")
          end
        end

        if @strict
          source.each_key do |key|
            raise ValidationError.new("#{path}.#{key} is not allowed") unless @fields.has_key?(key)
          end
        end
      end
    end

    module Types
      def self.any : Validator
        AnyValidator.new
      end

      def self.of(type : String.class) : Validator
        TypeValidator.new(:string)
      end

      def self.of(type : Int32.class) : Validator
        TypeValidator.new(:int32)
      end

      def self.of(type : Int64.class) : Validator
        TypeValidator.new(:int64)
      end

      def self.of(type : Float64.class) : Validator
        TypeValidator.new(:float64)
      end

      def self.of(type : Bool.class) : Validator
        TypeValidator.new(:bool)
      end

      def self.of(type : Hash.class) : Validator
        TypeValidator.new(:hash)
      end

      def self.of(type : Array.class) : Validator
        TypeValidator.new(:array)
      end

      def self.enum(values : Array(String)) : Validator
        EnumValidator.new(values)
      end

      def self.optional(inner : Validator) : Validator
        OptionalValidator.new(inner)
      end

      def self.array(item : Validator) : Validator
        ArrayValidator.new(item)
      end

      def self.object(fields : Hash(String, Validator), strict : Bool = true) : Validator
        ObjectValidator.new(fields, strict: strict)
      end
    end
  end
end
