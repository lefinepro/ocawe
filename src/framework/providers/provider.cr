require "json"
module OcaweCore
  module AI
    alias AnyHash = Hash(String, JSON::Any)

    struct TextGenerationRequest
      getter model : String
      getter system : String?
      getter prompt : String
      getter messages : Array(JSON::Any)?
      getter tools : Array(JSON::Any)?
      getter metadata : AnyHash
      getter api_key : String?
      getter base_url : String?

      def initialize(@model : String, @prompt : String, @system : String? = nil, @messages : Array(JSON::Any)? = nil, @tools : Array(JSON::Any)? = nil, @metadata : AnyHash = {} of String => JSON::Any, @api_key : String? = nil, @base_url : String? = nil)
      end
    end

    struct TextGenerationResponse
      getter provider : String
      getter model : String
      getter text : String
      getter tool_calls : Array(JSON::Any)?

      def initialize(@provider : String, @model : String, @text : String, @tool_calls : Array(JSON::Any)? = nil)
      end
    end

    module Provider
      abstract def generate_text(request : TextGenerationRequest) : TextGenerationResponse
    end
  end
end
