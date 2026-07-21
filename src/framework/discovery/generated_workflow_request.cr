require "json"
require "random/secure"
require "set"

module ACD
  module Discovery
    class GeneratedWorkflowValidationError < Exception
    end

    class GeneratedWorkflowConflictError < Exception
    end

    class GeneratedWorkflowPayloadTooLargeError < Exception
    end

    struct GeneratedWorkflowRequest
      MAX_BODY_BYTES = 512 * 1024
      ID_PATTERN     = /\A[a-z0-9][a-z0-9_-]{0,63}\z/
      ALLOWED_FIELDS = Set{
        "id", "workflow_id", "name", "description", "prompt", "schedule",
        "tag", "trigger_message", "trigger", "model", "conversation_id",
        "user_id", "environment_id",
      }

      getter id : String
      getter name : String
      getter description : String?
      getter prompt : String
      getter schedule : String?
      getter tag : String?
      getter trigger_message : String?
      getter model : String?
      getter conversation_id : String?
      getter user_id : String?
      getter environment_id : String?

      def initialize(
        @id : String,
        @name : String,
        @prompt : String,
        @description : String? = nil,
        @schedule : String? = nil,
        @tag : String? = nil,
        @trigger_message : String? = nil,
        @model : String? = nil,
        @conversation_id : String? = nil,
        @user_id : String? = nil,
        @environment_id : String? = nil,
      )
      end

      def self.parse(raw : String) : self
        raise GeneratedWorkflowValidationError.new("request body is required") if raw.strip.empty?
        if raw.bytesize > MAX_BODY_BYTES
          raise GeneratedWorkflowPayloadTooLargeError.new("request body exceeds #{MAX_BODY_BYTES} bytes")
        end

        body = JSON.parse(raw).as_h?
        raise GeneratedWorkflowValidationError.new("request body must be a JSON object") unless body

        unknown = body.keys.reject { |key| ALLOWED_FIELDS.includes?(key) }.sort
        unless unknown.empty?
          raise GeneratedWorkflowValidationError.new("unknown request fields: #{unknown.join(", ")}")
        end

        name = required_string(body, "name", 160).strip
        prompt = required_string(body, "prompt", 65_536)
        validate_single_line!(name, "name")
        validate_no_nul!(prompt, "prompt")

        requested_id = aliased_string(body, "id", "workflow_id", 64)
        id = requested_id || slug_for(name)
        validate_id!(id)

        description = optional_multiline(body, "description", 2_000)
        schedule = optional_single_line(body, "schedule", 2_048)
        tag = optional_single_line(body, "tag", 65)
        trigger_message = aliased_string(body, "trigger_message", "trigger", 2_048)
        model = optional_single_line(body, "model", 255)
        conversation_id = optional_single_line(body, "conversation_id", 255)
        user_id = optional_single_line(body, "user_id", 255)
        environment_id = optional_single_line(body, "environment_id", 255)
        validate_tag!(tag) if tag

        new(
          id: id,
          name: name,
          prompt: prompt,
          description: description,
          schedule: schedule,
          tag: tag,
          trigger_message: trigger_message,
          model: model,
          conversation_id: conversation_id,
          user_id: user_id,
          environment_id: environment_id,
        )
      rescue ex : JSON::ParseException
        raise GeneratedWorkflowValidationError.new("request body must contain valid JSON: #{ex.message}")
      end

      def metadata : Hash(String, JSON::Any)
        values = {} of String => JSON::Any
        add_metadata(values, "schedule", schedule)
        add_metadata(values, "tag", tag)
        add_metadata(values, "trigger_message", trigger_message)
        add_metadata(values, "conversation_id", conversation_id)
        add_metadata(values, "user_id", user_id)
        add_metadata(values, "environment_id", environment_id)
        values
      end

      def self.validate_id!(id : String) : Nil
        return if id.matches?(ID_PATTERN)
        raise GeneratedWorkflowValidationError.new("id must match [a-z0-9][a-z0-9_-]{0,63}")
      end

      private def self.required_string(body, key : String, max_size : Int32) : String
        value = body[key]? || raise GeneratedWorkflowValidationError.new("#{key} is required")
        string = value.as_s? || raise GeneratedWorkflowValidationError.new("#{key} must be a string")
        raise GeneratedWorkflowValidationError.new("#{key} must not be empty") if string.strip.empty?
        validate_size!(string, key, max_size)
        string
      end

      private def self.optional_string(body, key : String, max_size : Int32) : String?
        value = body[key]?
        return nil unless value
        return nil if value.raw.nil?

        string = value.as_s? || raise GeneratedWorkflowValidationError.new("#{key} must be a string or null")
        return nil if string.strip.empty?
        validate_size!(string, key, max_size)
        string
      end

      private def self.optional_single_line(body, key : String, max_size : Int32) : String?
        value = optional_string(body, key, max_size)
        return nil unless value
        normalized = value.strip
        validate_single_line!(normalized, key)
        normalized
      end

      private def self.optional_multiline(body, key : String, max_size : Int32) : String?
        value = optional_string(body, key, max_size)
        return nil unless value
        validate_no_nul!(value, key)
        value.strip
      end

      private def self.aliased_string(body, primary : String, alias_name : String, max_size : Int32) : String?
        primary_value = optional_single_line(body, primary, max_size)
        alias_value = optional_single_line(body, alias_name, max_size)
        if primary_value && alias_value && primary_value != alias_value
          raise GeneratedWorkflowValidationError.new("#{primary} and #{alias_name} must match when both are provided")
        end
        primary_value || alias_value
      end

      private def self.validate_size!(value : String, key : String, max_size : Int32) : Nil
        if value.size > max_size
          raise GeneratedWorkflowValidationError.new("#{key} exceeds #{max_size} characters")
        end
      end

      private def self.validate_no_nul!(value : String, key : String) : Nil
        if value.includes?('\0')
          raise GeneratedWorkflowValidationError.new("#{key} must not contain NUL characters")
        end
      end

      private def self.validate_single_line!(value : String, key : String) : Nil
        validate_no_nul!(value, key)
        if value.includes?('\n') || value.includes?('\r')
          raise GeneratedWorkflowValidationError.new("#{key} must be a single line")
        end
      end

      private def self.validate_tag!(tag : String) : Nil
        return if tag.matches?(/\A#?[^\s#\/\\]{1,64}\z/)
        raise GeneratedWorkflowValidationError.new("tag must be one token of at most 64 characters")
      end

      private def self.slug_for(name : String) : String
        slug = name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
        slug = slug[0, 64].gsub(/-+\z/, "") if slug.size > 64
        slug.empty? ? "workflow-#{Random::Secure.hex(6)}" : slug
      end

      private def add_metadata(values, key : String, value : String?) : Nil
        values[key] = JSON.parse(value.to_json) if value
      end
    end
  end
end
