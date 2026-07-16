require "json"
require "./default_function_handlers"

module Ocawe
  module Config
    enum LogLevel
      Debug
      Warning
      Critical

      def self.parse(value : String) : LogLevel
        case value.strip.downcase
        when "debug"
          Debug
        when "warning"
          Warning
        when "critical"
          Critical
        else
          Warning
        end
      end
    end

    struct StartSettings
      getter port : Int32
      getter log_level : LogLevel

      def initialize(@port : Int32 = 4111, @log_level : LogLevel = LogLevel::Warning)
      end
    end

    struct WorkflowSettings
      getter preferred_workflows_root : String

      def initialize(@preferred_workflows_root : String)
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

      def initialize(@adapter : String = "memory", @file_root : String = "./.ocawe/datasets")
      end
    end

    struct SchedulerSettings
      getter enabled : Bool
      getter min_workers : Int32
      getter max_workers : Int32
      getter target_queue_depth : Int32
      getter scale_up_cooldown_ms : Int32
      getter scale_down_cooldown_ms : Int32

      def initialize(
        @enabled : Bool = false,
        @min_workers : Int32 = 1,
        @max_workers : Int32 = 4,
        @target_queue_depth : Int32 = 2,
        @scale_up_cooldown_ms : Int32 = 500,
        @scale_down_cooldown_ms : Int32 = 5000,
      )
        @min_workers = normalize_non_negative(@min_workers)
        @max_workers = Math.max(@min_workers, normalize_positive(@max_workers, 1))
        @target_queue_depth = normalize_positive(@target_queue_depth, 1)
        @scale_up_cooldown_ms = normalize_non_negative(@scale_up_cooldown_ms)
        @scale_down_cooldown_ms = normalize_non_negative(@scale_down_cooldown_ms)
      end

      private def normalize_non_negative(value : Int32) : Int32
        value < 0 ? 0 : value
      end

      private def normalize_positive(value : Int32, fallback : Int32) : Int32
        value <= 0 ? fallback : value
      end
    end

    struct WebhookSettings
      getter enabled : Bool
      getter secret_env : String
      getter workspace_root : String
      getter default_workflow : String?
      getter allowed_repos : Array(String)
      getter allowed_refs : Array(String)

      def initialize(
        @enabled : Bool = false,
        @secret_env : String = "OCAWE_WEBHOOK_SECRET",
        @workspace_root : String = "./.ocawe/webhook-workspaces",
        @default_workflow : String? = nil,
        @allowed_repos : Array(String) = [] of String,
        @allowed_refs : Array(String) = [] of String,
      )
      end
    end

    struct FederationSettings
      getter auto_subscribe : Array(String)
      getter s2s_poll_interval_seconds : Int32
      getter s2s_http_timeout_seconds : Int32
      getter signatures_required : Bool
      getter local_actor : String
      getter local_key_id : String
      getter local_private_key_path : String

      def initialize(
        @auto_subscribe : Array(String) = [] of String,
        @s2s_poll_interval_seconds : Int32 = 15,
        @s2s_http_timeout_seconds : Int32 = 10,
        @signatures_required : Bool = true,
        @local_actor : String = "http://127.0.0.1:4111/actors/server",
        @local_key_id : String = "http://127.0.0.1:4111/actors/server#main-key",
        @local_private_key_path : String = "./.ocawe/federation-private.pem",
      )
      end
    end

    struct ApiSettings
      getter enabled : Array(String)

      def initialize(enabled : Array(String) = ["classic"] of String)
        normalized = enabled.map(&.strip.downcase).reject(&.empty?).uniq!
        normalized = normalized.map do |name|
          case name
          when "mastra"
            "classic"
          when "lefine"
            "federation"
          else
            name
          end
        end
        normalized = normalized.uniq
        @enabled = normalized.empty? ? ["classic"] of String : normalized
      end

      def enable?(name : String) : Bool
        @enabled.includes?(name.strip.downcase)
      end

      def federation_only? : Bool
        @enabled.size == 1 && @enabled[0] == "federation"
      end
    end

    struct TelemetrySettings
      getter enabled : Bool
      getter service_name : String
      getter service_version : String
      getter endpoint : String?
      getter headers : Hash(String, String)
      getter traces_enabled : Bool
      getter metrics_enabled : Bool
      getter logs_enabled : Bool
      getter exporter : String
      getter sample_ratio : Float64

      def initialize(
        @enabled : Bool = false,
        @service_name : String = "ocawe",
        @service_version : String = "unknown",
        @endpoint : String? = nil,
        @headers : Hash(String, String) = {} of String => String,
        @traces_enabled : Bool = true,
        @metrics_enabled : Bool = true,
        @logs_enabled : Bool = true,
        @exporter : String = "otlp_http",
        @sample_ratio : Float64 = 1.0,
      )
      end
    end

    struct Settings
      getter workflows : WorkflowSettings
      getter node_kinds : NodeKindSettings
      getter datasets : DatasetSettings
      getter federation : FederationSettings
      getter api : ApiSettings
      getter scheduler : SchedulerSettings
      getter webhooks : WebhookSettings
      getter functions : Hash(String, Ocawe::Workflow::FunctionHandler)
      getter workspace_bootstrap : Proc(Nil)?
      getter mcp : MCPSettings
      getter log_settings : LogSettings
      getter telemetry : TelemetrySettings

      def initialize(
        @workflows : WorkflowSettings,
        @node_kinds : NodeKindSettings = NodeKindSettings.new,
        @datasets : DatasetSettings = DatasetSettings.new,
        @federation : FederationSettings = FederationSettings.new,
        @api : ApiSettings = ApiSettings.new,
        @scheduler : SchedulerSettings = SchedulerSettings.new,
        @webhooks : WebhookSettings = WebhookSettings.new,
        @functions : Hash(String, Ocawe::Workflow::FunctionHandler) = {} of String => Ocawe::Workflow::FunctionHandler,
        @workspace_bootstrap : Proc(Nil)? = nil,
        @mcp : MCPSettings = MCPSettings.new,
        @log_settings : LogSettings = LogSettings.new,
        @telemetry : TelemetrySettings = TelemetrySettings.new,
      )
      end

      def self.default : Settings
        functions = DefaultFunctionHandlers.available

        new(
          workflows: WorkflowSettings.new(
            preferred_workflows_root: "./src/workflows"
          ),
          node_kinds: NodeKindSettings.new,
          datasets: DatasetSettings.new,
          federation: FederationSettings.new,
          api: ApiSettings.new,
          scheduler: SchedulerSettings.new,
          webhooks: WebhookSettings.new,
          functions: functions,
          workspace_bootstrap: nil,
          mcp: MCPSettings.new,
          log_settings: LogSettings.new,
          telemetry: TelemetrySettings.new,
        )
      end
    end

    struct LogSettings
      getter level : LogLevel

      def initialize(@level : LogLevel = LogLevel::Warning)
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
        @enabled : Bool = true,
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
        @dynamic_store_path : String = ".meta/mcp_servers.json",
      )
      end
    end
  end
end
