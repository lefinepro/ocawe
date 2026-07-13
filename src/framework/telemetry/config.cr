require "http/headers"
require "../config/settings"
require "../version"

module Ocawe
  module Telemetry
    struct EffectiveConfig
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

      def initialize(settings : Ocawe::Config::TelemetrySettings)
        sdk_disabled = EffectiveConfig.env_bool("OTEL_SDK_DISABLED")
        explicit_enabled = EffectiveConfig.env_bool("OCAWE_TELEMETRY_ENABLED")
        @enabled = sdk_disabled == true ? false : (explicit_enabled.nil? ? settings.enabled : explicit_enabled.not_nil!)
        @service_name = EffectiveConfig.env_string("OTEL_SERVICE_NAME") || settings.service_name
        @service_version = EffectiveConfig.env_string("OTEL_SERVICE_VERSION") || EffectiveConfig.normalized_service_version(settings.service_version)
        @endpoint = EffectiveConfig.env_string("OTEL_EXPORTER_OTLP_ENDPOINT") || settings.endpoint
        @headers = settings.headers.merge(EffectiveConfig.parse_headers_env(ENV["OTEL_EXPORTER_OTLP_HEADERS"]?))
        @traces_enabled = EffectiveConfig.signal_enabled?(settings.traces_enabled, "OTEL_TRACES_EXPORTER")
        @metrics_enabled = EffectiveConfig.signal_enabled?(settings.metrics_enabled, "OTEL_METRICS_EXPORTER")
        @logs_enabled = EffectiveConfig.signal_enabled?(settings.logs_enabled, "OTEL_LOGS_EXPORTER")
        @exporter = EffectiveConfig.normalize_exporter(EffectiveConfig.env_string("OCAWE_TELEMETRY_EXPORTER") || settings.exporter)
        @sample_ratio = EffectiveConfig.normalize_sample_ratio(EffectiveConfig.env_float("OTEL_TRACES_SAMPLER_ARG") || settings.sample_ratio)
      end

      def signal_endpoint(signal : String) : String?
        specific = EffectiveConfig.env_string("OTEL_EXPORTER_OTLP_#{signal.upcase}_ENDPOINT")
        return specific if specific
        return nil unless endpoint = @endpoint
        return endpoint if endpoint.ends_with?("/v1/#{signal}")
        "#{endpoint.rstrip('/')}/v1/#{signal}"
      end

      def http_headers : HTTP::Headers
        headers = HTTP::Headers.new
        @headers.each { |key, value| headers[key] = value }
        headers
      end

      def self.normalized_service_version(value : String) : String
        value == "unknown" ? OcaweCore::VERSION : value
      end

      def self.normalize_exporter(value : String) : String
        normalized = value.strip.downcase
        return "stdout" if normalized == "stdout" || normalized == "console"
        "otlp_http"
      end

      def self.normalize_sample_ratio(value : Float64) : Float64
        return 0.0 if value < 0.0
        return 1.0 if value > 1.0
        value
      end

      def self.signal_enabled?(default : Bool, env_key : String) : Bool
        value = ENV[env_key]?
        return default unless value
        normalized = value.strip.downcase
        return false if normalized == "none"
        true
      end

      def self.env_string(key : String) : String?
        value = ENV[key]?
        return nil unless value
        stripped = value.strip
        stripped.empty? ? nil : stripped
      end

      def self.env_bool(key : String) : Bool?
        value = env_string(key).try(&.downcase)
        return nil unless value
        return true if value == "true" || value == "1" || value == "yes"
        return false if value == "false" || value == "0" || value == "no"
        nil
      end

      def self.env_float(key : String) : Float64?
        env_string(key).try(&.to_f64?)
      end

      def self.parse_headers_env(value : String?) : Hash(String, String)
        headers = {} of String => String
        return headers unless value

        value.split(",").each do |entry|
          parts = entry.split("=", 2)
          next unless parts.size == 2
          key = parts[0].strip
          val = parts[1].strip
          headers[key] = val unless key.empty?
        end
        headers
      end
    end
  end
end
