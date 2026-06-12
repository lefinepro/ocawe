# Translator functions for Orator
# These register node_kind handlers for ActivityPub inbox/outbox operations

require "./converters.cr"

module Orator
  module Translators
    # Translator that converts OpenResponses/ChatCompletion request to ActivityPub
    # and sends it to a remote inbox
    class SendToInbox
      def self.translate(
        input : Hash(String, JSON::Any),
        context : Hash(String, JSON::Any)
      ) : Hash(String, JSON::Any)
        # Detect input format based on structure
        format = detect_format(input)
        
        actor_url = context["actor_url"]?.try(&.as_s?) || context["workflow_actor"]?.try(&.as_s?)
        local_domain = context["local_domain"]?.try(&.as_s?) || context["base_url"]?.try(&.as_s?)
        
        # Convert to ActivityPub based on detected format
        activity = case format
        when :openresponses
          converter = Orator::OpenResponsesToActivityPub.new(actor_url, local_domain)
          converter.convert(input)
        when :chat_completion
          converter = Orator::ChatCompletionToActivityPub.new(actor_url, local_domain)
          converter.convert(input)
        else
          raise ArgumentError.new("Unsupported input format")
        end
        
        # Store activity for outbox delivery
        {
          "activity" => JSON.parse(activity.to_json),
          "format" => JSON.parse(format.to_s.to_json),
          "original_input" => JSON.parse(input.to_json),
        } of String => JSON::Any
      end
      
      private def self.detect_format(input : Hash(String, JSON::Any)) : Symbol
        # OpenResponses has "input" field
        if input.has_key?("input")
          return :openresponses
        end
        
        # ChatCompletion has "messages" array
        if input.has_key?("messages")
          return :chat_completion
        end
        
        # Default to openresponses
        :openresponses
      end
    end
    
    # Translator that receives ActivityPub activities from outbox
    # and converts them back to OpenResponses/ChatCompletion format
    class ReceiveFromOutbox
      def self.translate(
        input : Hash(String, JSON::Any),
        context : Hash(String, JSON::Any)
      ) : Hash(String, JSON::Any)
        # Extract activity from input
        activity = input["activity"]?.try(&.as_h?)
        raise ArgumentError.new("No activity found in input") unless activity
        
        # Get original format if available
        format = input["format"]?.try(&.as_s?).try(&.to_sym) || :openresponses
        original_model = input["model"]?.try(&.as_s?) || context["model"]?.try(&.as_s?) || "unknown"
        
        # Convert from ActivityPub based on target format
        response = case format
        when :openresponses
          converter = Orator::ActivityPubToOpenResponses.new
          converter.convert(activity, original_model)
        when :chat_completion
          converter = Orator::ActivityPubToChatCompletion.new
          converter.convert(activity, original_model)
        else
          converter = Orator::ActivityPubToOpenResponses.new
          converter.convert(activity, original_model)
        end
        
        response
      end
    end
  end
end

# Note: Node kinds registration happens when Cawfile is loaded by the framework
# The framework will call Ocawe::RegistryApi.node_kind() at runtime

# Extend WorkflowDefinition with Orator DSL methods
# These methods will be available when require'd in Cawfile
module Ocawe
  module Workflow
    class WorkflowDefinition
      # Send input to remote inbox as ActivityPub
      def send_to_inbox(
        id : String = "send_to_inbox",
        input_schema : Ocawe::Workflows::DSL::Validator? = nil,
        output_schema : Ocawe::Workflows::DSL::Validator? = nil
      ) : self
        step(
          Ocawe::NodeKind.new("send_to_inbox"),
          id: id,
          input_schema: input_schema,
          output_schema: output_schema,
        )
      end
      
      # Receive activities from outbox and convert back to API format
      def recevie_from_outbox(
        id : String = "recevie_from_outbox",
        input_schema : Ocawe::Workflows::DSL::Validator? = nil,
        output_schema : Ocawe::Workflows::DSL::Validator? = nil
      ) : self
        step(
          Ocawe::NodeKind.new("recevie_from_outbox"),
          id: id,
          input_schema: input_schema,
          output_schema: output_schema,
        )
      end
    end
  end
end
