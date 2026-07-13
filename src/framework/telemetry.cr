require "opentelemetry-sdk"
require "./telemetry/config"

module Ocawe
  module Telemetry
    alias AttributeValue = String | Bool | Int32 | Int64 | Float64

    struct MetricPoint
      getter name : String
      getter kind : String
      getter value : Float64
      getter unit : String
      getter attributes : Hash(String, AttributeValue)
      getter time_unix_nano : UInt64

      def initialize(@name, @kind, @value, @unit, @attributes, @time_unix_nano)
      end
    end

    struct LogRecord
      getter severity : String
      getter body : String
      getter attributes : Hash(String, AttributeValue)
      getter trace_id : String?
      getter span_id : String?
      getter time_unix_nano : UInt64

      def initialize(@severity, @body, @attributes, @trace_id, @span_id, @time_unix_nano)
      end
    end

    @@config = EffectiveConfig.new(Ocawe::Config::TelemetrySettings.new)
    @@exporter = nil.as(OtlpHttpExporter?)
    @@configured = false
    @@lock = Mutex.new
    @@metrics = [] of MetricPoint
    @@logs = [] of LogRecord

    def self.configure(settings : Ocawe::Config::TelemetrySettings) : Nil
      config = EffectiveConfig.new(settings)
      @@lock.synchronize do
        @@config = config
        @@exporter = OtlpHttpExporter.new(config)
        @@configured = true
        @@metrics.clear
        @@logs.clear
      end
      configure_tracing(config)
    end

    def self.enabled? : Bool
      @@config.enabled
    end

    def self.traces_enabled? : Bool
      @@config.enabled && @@config.traces_enabled
    end

    def self.metrics_enabled? : Bool
      @@config.enabled && @@config.metrics_enabled
    end

    def self.logs_enabled? : Bool
      @@config.enabled && @@config.logs_enabled
    end

    def self.start_span(name : String, attributes : Hash(String, AttributeValue) = {} of String => AttributeValue, kind : String = "internal") : OpenTelemetry::Span?
      return nil unless traces_enabled?
      span = OpenTelemetry.tracer.in_span(name)
      apply_span_kind(span, kind)
      attributes.each { |key, value| set_span_attribute(span, key, value) }
      span
    rescue ex
      STDERR.puts "[ocawe] telemetry span start failed: #{ex.message || ex.class.name}"
      nil
    end

    def self.apply_traceparent(value : String?) : Nil
      return unless traces_enabled?
      return unless value
      trace_parent = OpenTelemetry::Propagation::TraceContext::TraceParent.from_string(value)
      tracer = OpenTelemetry.tracer
      tracer.span_context.trace_id = trace_parent.trace_id
      tracer.span_context.span_id = trace_parent.span_id
    rescue
    end

    def self.finish_span(span : OpenTelemetry::Span?, status : String? = nil, error : String? = nil, attributes : Hash(String, AttributeValue) = {} of String => AttributeValue) : Nil
      return unless span
      attributes.each { |key, value| set_span_attribute(span, key, value) }
      if error
        span.status.error!(error)
      elsif status && (status == "success" || status == "ok")
        span.status.ok!
      end
      OpenTelemetry.tracer.close_span(span)
    rescue ex
      STDERR.puts "[ocawe] telemetry span finish failed: #{ex.message || ex.class.name}"
    end

    def self.in_span(name : String, attributes : Hash(String, AttributeValue) = {} of String => AttributeValue, kind : String = "internal", &)
      span = start_span(name, attributes, kind)
      begin
        yield span
      rescue ex
        finish_span(span, status: "error", error: ex.message)
        raise ex
      else
        finish_span(span, status: "success")
      end
    end

    def self.increment(name : String, value : Number = 1, unit : String = "1", attributes : Hash(String, AttributeValue) = {} of String => AttributeValue) : Nil
      record_metric(name, "counter", value.to_f64, unit, attributes)
    end

    def self.histogram(name : String, value : Number, unit : String, attributes : Hash(String, AttributeValue) = {} of String => AttributeValue) : Nil
      record_metric(name, "histogram", value.to_f64, unit, attributes)
    end

    def self.log(severity : String, body : String, attributes : Hash(String, AttributeValue) = {} of String => AttributeValue) : Nil
      return unless logs_enabled?
      trace_id, span_id = current_trace_ids
      record = LogRecord.new(severity, body, attributes, trace_id, span_id, now_unix_nano)
      exporter = nil.as(OtlpHttpExporter?)
      logs = [] of LogRecord
      @@lock.synchronize do
        @@logs << record
        logs << record
        exporter = @@exporter
      end
      export_logs(logs, exporter)
    end

    def self.flush : Nil
      metrics = [] of MetricPoint
      logs = [] of LogRecord
      exporter = nil.as(OtlpHttpExporter?)
      @@lock.synchronize do
        metrics = @@metrics.dup
        logs = @@logs.dup
        @@metrics.clear
        @@logs.clear
        exporter = @@exporter
      end
      export_metrics(metrics, exporter)
      export_logs(logs, exporter)
    end

    def self.metrics_snapshot : Array(MetricPoint)
      @@lock.synchronize { @@metrics.dup }
    end

    def self.logs_snapshot : Array(LogRecord)
      @@lock.synchronize { @@logs.dup }
    end

    def self.traceparent : String?
      return nil unless span = OpenTelemetry.current_span
      "00-#{span.context.trace_id.hexstring}-#{span.context.span_id.hexstring}-01"
    rescue
      nil
    end

    def self.current_trace_ids : Tuple(String?, String?)
      if span = OpenTelemetry.current_span
        {span.context.trace_id.hexstring, span.context.span_id.hexstring}
      else
        {nil, nil}
      end
    rescue
      {nil, nil}
    end

    private def self.configure_tracing(config : EffectiveConfig) : Nil
      if !config.enabled || !config.traces_enabled
        OpenTelemetry.configure do |otel|
          otel.service_name = config.service_name
          otel.service_version = config.service_version
          otel.exporter = OpenTelemetry::Exporter.new(variant: :null)
        end
        return
      end

      OpenTelemetry.configure do |otel|
        otel.service_name = config.service_name
        otel.service_version = config.service_version
        if config.sample_ratio < 1.0
          otel.sampler = OpenTelemetry::Sampler::TraceIdRatioBased.new(config.sample_ratio)
        end
        if config.exporter == "stdout"
          otel.exporter = OpenTelemetry::Exporter.new(variant: :stdout)
        else
          otel.exporter = OpenTelemetry::Exporter.new(variant: :http) do |exporter|
            http_exporter = exporter.as(OpenTelemetry::Exporter::Http)
            if endpoint = config.signal_endpoint("traces")
              http_exporter.endpoint = endpoint
            end
            http_exporter.headers = config.http_headers
          end
        end
      end
    rescue ex
      STDERR.puts "[ocawe] telemetry trace configuration failed: #{ex.message || ex.class.name}"
    end

    private def self.record_metric(name : String, kind : String, value : Float64, unit : String, attributes : Hash(String, AttributeValue)) : Nil
      return unless metrics_enabled?
      point = MetricPoint.new(name, kind, value, unit, attributes, now_unix_nano)
      @@lock.synchronize { @@metrics << point }
    end

    private def self.export_metrics(points : Array(MetricPoint), exporter : OtlpHttpExporter?) : Nil
      return if points.empty?
      if @@config.exporter == "stdout"
        points.each { |point| puts({"telemetry" => "metric", "name" => point.name, "value" => point.value, "attributes" => point.attributes}.to_json) }
      else
        exporter.try(&.export_metrics(points))
      end
    end

    private def self.export_logs(records : Array(LogRecord), exporter : OtlpHttpExporter?) : Nil
      return if records.empty?
      if @@config.exporter == "stdout"
        records.each { |record| puts({"telemetry" => "log", "severity" => record.severity, "body" => record.body, "attributes" => record.attributes}.to_json) }
      else
        exporter.try(&.export_logs(records))
      end
    end

    private def self.apply_span_kind(span : OpenTelemetry::Span, kind : String) : Nil
      case kind
      when "server"
        span.server!
      when "client"
        span.client!
      when "producer"
        span.producer!
      when "consumer"
        span.consumer!
      else
        span.internal!
      end
    end

    private def self.set_span_attribute(span : OpenTelemetry::Span, key : String, value : AttributeValue) : Nil
      span.set_attribute(key, value)
    rescue
    end

    private def self.now_unix_nano : UInt64
      (Time.utc - Time::UNIX_EPOCH).total_nanoseconds.to_u64
    end
  end
end

require "./telemetry/otlp_http_exporter"
