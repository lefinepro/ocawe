require "json"

module ACP
  # JSON-RPC 2.0 base types

  struct JsonRpcRequest
    include JSON::Serializable

    property jsonrpc : String = "2.0"
    property id : Int32 | String | Nil
    property method : String
    property params : JSON::Any?
  end

  struct JsonRpcResponse
    include JSON::Serializable

    property jsonrpc : String = "2.0"
    property id : Int32 | String | Nil
    property result : JSON::Any?
    property error : JsonRpcError?
  end

  struct JsonRpcNotification
    include JSON::Serializable

    property jsonrpc : String = "2.0"
    property method : String
    property params : JSON::Any?
  end

  struct JsonRpcError
    include JSON::Serializable

    property code : Int32
    property message : String
    property data : JSON::Any?
  end

  # ACP Protocol Types

  struct InitializeParams
    include JSON::Serializable

    property protocolVersion : Int32
    property clientCapabilities : ClientCapabilities
    property clientInfo : ClientInfo?
  end

  struct ClientCapabilities
    include JSON::Serializable

    property fs : FsCapabilities?
    property terminal : Bool?
  end

  struct FsCapabilities
    include JSON::Serializable

    property readTextFile : Bool?
    property writeTextFile : Bool?
  end

  struct ClientInfo
    include JSON::Serializable

    property name : String
    property title : String?
    property version : String?
  end

  struct InitializeResult
    include JSON::Serializable

    property protocolVersion : Int32
    property agentCapabilities : AgentCapabilities
    property agentInfo : AgentInfo?
    property authMethods : JSON::Any?
  end

  struct AgentCapabilities
    include JSON::Serializable

    property loadSession : Bool?
    property promptCapabilities : PromptCapabilities?
    property mcpCapabilities : McpCapabilities?
    property auth : AuthCapabilities?
    property sessionCapabilities : SessionCapabilities?
  end

  struct PromptCapabilities
    include JSON::Serializable

    property image : Bool?
    property audio : Bool?
    property embeddedContext : Bool?
  end

  struct McpCapabilities
    include JSON::Serializable

    property http : Bool?
    property sse : Bool?
  end

  struct AuthCapabilities
    include JSON::Serializable

    property logout : JSON::Any?
  end

  struct SessionCapabilities
    include JSON::Serializable

    property delete : JSON::Any?
    property close : JSON::Any?
    property resume : JSON::Any?
    property additionalDirectories : JSON::Any?
  end

  struct AgentInfo
    include JSON::Serializable

    property name : String
    property title : String?
    property version : String?
  end

  struct SessionNewParams
    include JSON::Serializable

    property cwd : String
    property mcpServers : Array(JSON::Any)?
    property additionalDirectories : Array(String)?
  end

  struct SessionNewResult
    include JSON::Serializable

    property sessionId : String
    property models : JSON::Any?
    property configOptions : JSON::Any?
  end

  struct SessionPromptParams
    include JSON::Serializable

    property sessionId : String
    property prompt : Array(ContentBlock)
  end

  struct ContentBlock
    include JSON::Serializable

    property type : String
    property text : String?
    property uri : String?
    property mimeType : String?
    property data : String?

    def self.text(text : String) : ContentBlock
      ContentBlock.from_json({
        "type" => "text",
        "text" => text
      }.to_json)
    end

    def self.resource(uri : String, mime_type : String, text : String) : ContentBlock
      ContentBlock.from_json({
        "type" => "resource",
        "uri" => uri,
        "mimeType" => mime_type,
        "text" => text
      }.to_json)
    end
  end

  struct SessionPromptResult
    include JSON::Serializable

    property stopReason : String
  end

  struct SessionUpdate
    include JSON::Serializable

    property sessionId : String
    property update : UpdatePayload
  end

  struct UpdatePayload
    include JSON::Serializable

    property sessionUpdate : String
    property messageId : String?
    property content : ContentBlock?
    property toolCallId : String?
    property title : String?
    property kind : String?
    property status : String?
    property entries : Array(JSON::Any)?
  end

  struct SessionCancelParams
    include JSON::Serializable

    property sessionId : String
  end

  # Error codes
  module ErrorCode
    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603
  end

  class ProtocolError < Exception
    getter code : Int32
    getter data : JSON::Any?

    def initialize(message : String, @code : Int32, @data : JSON::Any? = nil)
      detail = @data ? "#{message}: #{@data.not_nil!.to_json}" : message
      super(detail)
    end
  end
end
