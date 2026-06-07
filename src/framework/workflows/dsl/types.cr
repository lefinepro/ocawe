require "json"

module Ocawe
  module Workflows
    module DSL
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

      getter kind : Symbol

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

      getter values : Array(String)

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

      getter inner : Validator

      def initialize(@inner : Validator)
      end

      def validate(value : JSON::Any, path : String = "$") : Nil
        return if value.raw.nil?
        @inner.validate(value, path)
      end
    end

    class ArrayValidator
      include Validator

      getter item : Validator

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

      getter fields : Hash(String, Validator)
      getter strict : Bool

      def initialize(fields : Hash(String, V), @strict : Bool = true) forall V
        @fields = {} of String => Validator
        fields.each do |key, validator|
          @fields[key] = validator.as(Validator)
        end
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

      def self.object(fields : Hash(String, V), strict : Bool = true) : Validator forall V
        ObjectValidator.new(fields, strict: strict)
      end
    end

    module Compatibility
      extend self

      def ensure_output_superset!(input_schema : Validator, output_schema : Validator) : Nil
        ensure_superset!(output_schema, input_schema, "$")
      end

      private def ensure_superset!(output_schema : Validator, input_schema : Validator, path : String) : Nil
        return if output_schema.is_a?(AnyValidator) && !input_schema.is_a?(AnyValidator)
        if input_schema.is_a?(AnyValidator)
          raise ValidationError.new("#{path}: output schema must be Schema::Types.any to cover Schema::Types.any") unless output_schema.is_a?(AnyValidator)
          return
        end

        case {output_schema, input_schema}
        when {AnyValidator, _}
          return
        when {TypeValidator, TypeValidator}
          ensure_type_superset!(output_schema, input_schema, path)
        when {EnumValidator, EnumValidator}
          input_values = input_schema.values
          output_values = output_schema.values
          missing = input_values.reject { |val| output_values.includes?(val) }
          unless missing.empty?
            raise ValidationError.new("#{path}: output enum is missing input values #{missing.join(", ")}")
          end
        when {OptionalValidator, OptionalValidator}
          ensure_superset!(output_schema.inner, input_schema.inner, path)
        when {OptionalValidator, _}
          ensure_superset!(output_schema.inner, input_schema, path)
        when {_, OptionalValidator}
          raise ValidationError.new("#{path}: output schema must allow null/optional values")
        when {ArrayValidator, ArrayValidator}
          ensure_superset!(output_schema.item, input_schema.item, "#{path}[]")
        when {ObjectValidator, ObjectValidator}
          ensure_object_superset!(output_schema, input_schema, path)
        else
          raise ValidationError.new("#{path}: incompatible schema validators #{input_schema.class} -> #{output_schema.class}")
        end
      end

      private def ensure_type_superset!(output_schema : TypeValidator, input_schema : TypeValidator, path : String) : Nil
        output_kind = output_schema.kind
        input_kind = input_schema.kind
        return if output_kind == input_kind

        if output_kind == :float64 && (input_kind == :int32 || input_kind == :int64)
          return
        end

        if output_kind == :int64 && input_kind == :int32
          return
        end

        raise ValidationError.new("#{path}: output type #{output_kind} does not cover input type #{input_kind}")
      end

      private def ensure_object_superset!(output_schema : ObjectValidator, input_schema : ObjectValidator, path : String) : Nil
        input_schema.fields.each do |key, input_field_validator|
          output_field_validator = output_schema.fields[key]?
          if output_field_validator
            if input_field_validator.is_a?(OptionalValidator) && !output_field_validator.is_a?(OptionalValidator)
              raise ValidationError.new("#{path}.#{key}: output field must remain optional")
            end
            ensure_superset!(output_field_validator, input_field_validator, "#{path}.#{key}")
            next
          end

          if output_schema.strict
            raise ValidationError.new("#{path}.#{key}: output schema is missing input field")
          end
        end

        output_schema.fields.each do |key, output_field_validator|
          next if input_schema.fields.has_key?(key)
          next if output_field_validator.is_a?(OptionalValidator)
          raise ValidationError.new("#{path}.#{key}: output schema adds required field not present in input schema")
        end

        if input_schema.strict == false && output_schema.strict
          raise ValidationError.new("#{path}: output strict schema cannot cover non-strict input schema")
        end
      end
    end
  end
  end
end
