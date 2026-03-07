require "json"
require "set"

module Cogni
  module Logging
    class WorkflowLogger
      LEVELS = Set{"trace", "debug", "info", "warn", "error", "fatal"}

      def initialize(@workflow_id : String, @run_id : String)
        @warned_transport_targets = Set(String).new
      end

      def run_started(config : Hash(String, JSON::Any)?) : Nil
        emit("info", "run_started", "workflow run started", nil, config)
      end

      def run_completed(config : Hash(String, JSON::Any)?) : Nil
        emit("info", "run_completed", "workflow run completed", nil, config)
      end

      def run_suspended(config : Hash(String, JSON::Any)?) : Nil
        emit("warn", "run_suspended", "workflow run suspended", nil, config)
      end

      def run_failed(config : Hash(String, JSON::Any)?, message : String?) : Nil
        emit("error", "run_failed", message || "workflow run failed", nil, config)
      end

      def node_started(node_id : String, config : Hash(String, JSON::Any)?) : Nil
        emit("debug", "node_started", "node started", node_id, config)
      end

      def node_completed(node_id : String, config : Hash(String, JSON::Any)?) : Nil
        emit("info", "node_completed", "node completed", node_id, config)
      end

      def node_failed(node_id : String, config : Hash(String, JSON::Any)?, message : String?) : Nil
        emit("error", "node_failed", message || "node failed", node_id, config)
      end

      private def emit(default_level : String, event : String, message : String, node_id : String?, config : Hash(String, JSON::Any)?) : Nil
        return unless config
        active = config
        return unless console_enabled?(active)

        level = active["level"]?.try(&.as_s?) || default_level
        level = default_level unless LEVELS.includes?(level)

        payload = {
          "timestamp" => JSON.parse(Time.utc.to_s.to_json),
          "workflow_id" => JSON.parse(@workflow_id.to_json),
          "run_id" => JSON.parse(@run_id.to_json),
          "event" => JSON.parse(event.to_json),
          "message" => JSON.parse(message.to_json),
        } of String => JSON::Any

        if name = active["name"]?.try(&.as_s?)
          payload["name"] = JSON.parse(name.to_json)
        end
        payload["node_id"] = JSON.parse(node_id.to_json) if node_id

        apply_formatters!(payload, active["formatters"]?.try(&.as_h?), level)
        puts payload.to_json
      end

      private def apply_formatters!(payload : Hash(String, JSON::Any), formatters : Hash(String, JSON::Any)?, level : String) : Nil
        level_key = formatters.try { |f| f["levelKey"]?.try(&.as_s?) } || "level"
        payload[level_key] = JSON.parse(level.to_json)

        static_fields = formatters.try { |f| f["static"]?.try(&.as_h?) }
        return unless static_fields
        static_fields.each { |k, v| payload[k] = JSON.parse(v.to_json) }
      end

      private def console_enabled?(config : Hash(String, JSON::Any)) : Bool
        transports = config["transports"]?.try(&.as_a?)
        override_default = config["overrideDefaultTransports"]?.try(&.raw) == true

        return true unless transports

        explicit_console = false
        transports.each do |entry|
          transport = entry.as_h?
          next unless transport
          target = transport["target"]?.try(&.as_s?) || transport["type"]?.try(&.as_s?) || ""
          if target.downcase == "console"
            explicit_console = true
            next
          end

          warn_unsupported_transport(target) unless target.empty?
        end

        return explicit_console if override_default
        true
      end

      private def warn_unsupported_transport(target : String) : Nil
        return if @warned_transport_targets.includes?(target)
        @warned_transport_targets << target

        warning = {
          "timestamp" => JSON.parse(Time.utc.to_s.to_json),
          "workflow_id" => JSON.parse(@workflow_id.to_json),
          "run_id" => JSON.parse(@run_id.to_json),
          "level" => JSON.parse("warn".to_json),
          "event" => JSON.parse("logger_transport_unsupported".to_json),
          "message" => JSON.parse("unsupported logger transport '#{target}', console only".to_json),
        } of String => JSON::Any
        puts warning.to_json
      end
    end
  end
end
