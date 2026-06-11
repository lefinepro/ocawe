require "json"
module OcaweCore
  module AI
    alias AnyHash = Hash(String, JSON::Any)

    struct TextGenerationRequest
      getter model : String
      getter system : String?
      getter prompt : String
      getter metadata : AnyHash

      def initialize(@model : String, @prompt : String, @system : String? = nil, @metadata : AnyHash = {} of String => JSON::Any)
      end
    end

    struct TextGenerationResponse
      getter provider : String
      getter model : String
      getter text : String

      def initialize(@provider : String, @model : String, @text : String)
      end
    end

    module Provider
      abstract def generate_text(request : TextGenerationRequest) : TextGenerationResponse
    end
  end
end
