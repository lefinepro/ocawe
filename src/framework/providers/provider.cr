require "json"
module OcaweCore
  module AI
    alias AnyHash = Hash(String, JSON::Any)

    struct TokenUsage
      getter prompt_tokens : Int64?
      getter completion_tokens : Int64?
      getter total_tokens : Int64?

      def initialize(@prompt_tokens : Int64? = nil, @completion_tokens : Int64? = nil, @total_tokens : Int64? = nil)
      end

      def self.from_payload(payload : JSON::Any) : TokenUsage?
        usage = payload["usage"]?.try(&.as_h?)
        return unless usage

        prompt = token_count(usage["prompt_tokens"]? || usage["input_tokens"]?)
        completion = token_count(usage["completion_tokens"]? || usage["output_tokens"]?)
        total = token_count(usage["total_tokens"]?)
        return unless prompt || completion || total

        new(prompt, completion, total || (prompt && completion ? prompt + completion : nil))
      end

      private def self.token_count(value : JSON::Any?) : Int64?
        return unless value
        count = value.as_i?.try(&.to_i64) || value.as_f?.try(&.to_i64) || value.as_s?.try(&.to_i64?)
        count if count && count >= 0
      end
    end

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
      getter usage : TokenUsage?

      def initialize(@provider : String, @model : String, @text : String, @tool_calls : Array(JSON::Any)? = nil, @usage : TokenUsage? = nil)
      end
    end

    module Provider
      abstract def generate_text(request : TextGenerationRequest) : TextGenerationResponse
    end
  end
end
