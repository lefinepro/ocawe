require "json"
require "./default_function_handlers"

module Cogni
  module Config
    struct WorkflowSettings
      getter preferred_workflows_root : String
      getter fallback_workflows_root : String

      def initialize(@preferred_workflows_root : String, @fallback_workflows_root : String)
      end
    end

    struct NodeKindSettings
      getter enabled : Array(String)

      def initialize(@enabled : Array(String) = [] of String)
      end
    end

    struct DatasetSettings
      getter adapter : String
      getter file_root : String

      def initialize(@adapter : String = "memory", @file_root : String = "./.cogni/datasets")
      end
    end

    struct Settings
      getter workflows : WorkflowSettings
      getter node_kinds : NodeKindSettings
      getter datasets : DatasetSettings
      getter functions : Hash(String, Cogni::Workflow::FunctionHandler)
      getter workspace_bootstrap : Proc(Nil)?
      getter mcp : MCPSettings

      def initialize(
        @workflows : WorkflowSettings,
        @node_kinds : NodeKindSettings = NodeKindSettings.new,
        @datasets : DatasetSettings = DatasetSettings.new,
        @functions : Hash(String, Cogni::Workflow::FunctionHandler) = {} of String => Cogni::Workflow::FunctionHandler,
        @workspace_bootstrap : Proc(Nil)? = nil,
        @mcp : MCPSettings = MCPSettings.new
      )
      end

      def self.default : Settings
        functions = {
          "agent_opencode" => DefaultFunctionHandlers.agent_opencode,
          "agent_codex" => DefaultFunctionHandlers.agent_codex,
          "agent_cliproxy" => DefaultFunctionHandlers.agent_cliproxy,
        } of String => Cogni::Workflow::FunctionHandler

        new(
          workflows: WorkflowSettings.new(
            preferred_workflows_root: "./src/workflows",
            fallback_workflows_root: "./src/workflows"
          ),
          node_kinds: NodeKindSettings.new,
          datasets: DatasetSettings.new,
          functions: functions,
          workspace_bootstrap: nil,
          mcp: MCPSettings.new,
        )
      end
    end

    struct MCPServerSettings
      include JSON::Serializable

      getter id : String
      getter transport : String
      getter command : String?
      getter args : Array(String)
      getter env : Hash(String, String)
      getter url : String?
      getter bearer_token : String?
      getter enabled : Bool

      def initialize(
        @id : String,
        @transport : String,
        @command : String? = nil,
        @args : Array(String) = [] of String,
        @env : Hash(String, String) = {} of String => String,
        @url : String? = nil,
        @bearer_token : String? = nil,
        @enabled : Bool = true
      )
      end
    end

    struct MCPHTTPServerSettings
      getter enabled : Bool
      getter path : String
      getter bearer_token : String?

      def initialize(@enabled : Bool = false, @path : String = "/mcp", @bearer_token : String? = nil)
      end
    end

    struct MCPDefaultsSettings
      getter request_timeout_ms : Int32
      getter reconnect_backoff_ms : Int32

      def initialize(@request_timeout_ms : Int32 = 15000, @reconnect_backoff_ms : Int32 = 3000)
      end
    end

    struct MCPSettings
      getter servers : Array(MCPServerSettings)
      getter http_server : MCPHTTPServerSettings
      getter defaults : MCPDefaultsSettings
      getter dynamic_store_path : String

      def initialize(
        @servers : Array(MCPServerSettings) = [] of MCPServerSettings,
        @http_server : MCPHTTPServerSettings = MCPHTTPServerSettings.new,
        @defaults : MCPDefaultsSettings = MCPDefaultsSettings.new,
        @dynamic_store_path : String = ".meta/mcp_servers.json"
      )
      end
    end
  end
end
