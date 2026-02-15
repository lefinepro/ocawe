module CogniCore
  module OpenResponses
    struct ToolFunction
      include JSON::Serializable

      getter name : String
      getter description : String?
      getter parameters : Hash(String, JSON::Any)?
    end

    struct ToolSpec
      include JSON::Serializable

      getter type : String
      getter function : ToolFunction
    end

    struct InputItem
      include JSON::Serializable

      getter type : String
      getter text : String?
      getter function_output : String?
    end

    struct Request
      include JSON::Serializable

      getter model : String
      getter input : JSON::Any
      getter workflow : String?
      getter workflow_input : Hash(String, JSON::Any)?
      getter tools : Array(ToolSpec)?
      getter stream : Bool?
      getter metadata : Hash(String, JSON::Any)?
    end

    struct OutputItem
      include JSON::Serializable

      getter type : String
      getter text : String?
      getter step_name : String?
    end

    struct Usage
      include JSON::Serializable

      getter input_tokens : Int32
      getter output_tokens : Int32
    end

    struct Response
      include JSON::Serializable

      getter id : String
      getter object : String
      getter created_at : Int64
      getter completed_at : Int64?
      getter status : String
      getter model : String
      getter output : Array(OutputItem)
      getter usage : Usage?
    end
  end
end
