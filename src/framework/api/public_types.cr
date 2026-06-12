# Public API request/response types for Cawfile struct declarations.
# Including these modules in a struct brings in the actual schema fields
# for the corresponding API format.
#
# Usage in Cawfile:
#   struct InputSimple
#     include Api::OpenResponses::Request
#     include Api::MastraAPI::Request
#     include Api::ChatCompletionAPI::Request
#   end
#   struct OutputSimple
#     include Api::OpenResponses::Response
#     include Api::MastraAPI::Response
#     include Api::ChatCompletionAPI::Response
#   end
require "json"
require "./acp"

module Api
  # Shared base fields present in most request types.
  module BaseRequest
    include JSON::Serializable
    property model : String?
    property stream : Bool?
    property metadata : Hash(String, JSON::Any)?
  end

  module OpenResponses
    struct OutputItem
      include JSON::Serializable
      property type : String
      property text : String?
      property step_name : String?
    end

    struct Usage
      include JSON::Serializable
      property input_tokens : Int32
      property output_tokens : Int32
    end

    # Mirrors POST /v1/responses request body.
    module Request
      include BaseRequest
      property input : JSON::Any
      property workflow : String?
      property workflow_input : Hash(String, JSON::Any)?
      property tools : Array(Hash(String, JSON::Any))?
    end

    # Mirrors POST /v1/responses response body.
    module Response
      include JSON::Serializable
      property id : String
      property object : String
      property created_at : Int64
      property completed_at : Int64?
      property status : String
      property model : String
      property output : Array(OutputItem)
      property usage : Usage?
    end
  end

  module MastraAPI
    struct Message
      include JSON::Serializable
      property role : String
      property content : String
    end

    # Mirrors Mastra agent generate/stream request body.
    module Request
      include BaseRequest
      property messages : Array(Message)?
      property input : String?
      property prompt : String?
    end

    # Mirrors Mastra agent generate response body.
    module Response
      include JSON::Serializable
      property text : String?
      property reasoning : String?
      property toolCalls : Array(Hash(String, JSON::Any))?
      property object : JSON::Any?
    end
  end

  module ChatCompletionAPI
    struct Message
      include JSON::Serializable
      property role : String
      property content : String
    end

    struct Choice
      include JSON::Serializable
      property index : Int32
      property message : Message
      property finish_reason : String
    end

    struct Usage
      include JSON::Serializable
      property prompt_tokens : Int32
      property completion_tokens : Int32
      property total_tokens : Int32
    end

    # Mirrors POST /v1/chat/completions request body.
    module Request
      include BaseRequest
      property messages : Array(Message)
      property temperature : Float64?
      property max_tokens : Int32?
    end

    # Mirrors POST /v1/chat/completions response body.
    module Response
      include JSON::Serializable
      property id : String
      property object : String
      property created : Int64
      property model : String
      property choices : Array(Choice)
      property usage : Usage?
    end
  end

  # Models API opt-in marker.
  # Including this in a Cawfile struct enables GET /v1/models endpoint.
  # Usage in Cawfile:
  #   struct InputSimple
  #     include Api::Models
  #   end
  module Models
    # Marker module - no fields needed, just triggers endpoint registration
  end
end
