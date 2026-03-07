module CogniCore
  module Memory
    enum MemoryType
      MessageHistory
      Working
      SemanticRecall
      Observational
    end

    struct MemoryRecord
      include JSON::Serializable

      getter type : String
      getter key : String
      getter value : String
      getter metadata : Hash(String, JSON::Any)?
      getter created_at : Int64
    end
  end
end
