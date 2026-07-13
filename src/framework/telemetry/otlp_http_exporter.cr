require "http/client"
require "json"
require "./config"

module Ocawe
  module Telemetry
    class OtlpHttpExporter
      def initialize(@config : EffectiveConfig)
      end

      def export_metrics(points : Array(MetricPoint)) : Nil
        return if points.empty?
        return unless endpoint = @config.signal_endpoint("metrics")
        post_json(endpoint, metrics_payload(points))
      end

      def export_logs(records : Array(LogRecord)) : Nil
        return if records.empty?
        return unless endpoint = @config.signal_endpoint("logs")
        post_json(endpoint, logs_payload(records))
      end

      private def post_json(endpoint : String, body : String) : Nil
        headers = @config.http_headers
        headers["Content-Type"] = "application/json"
        response = HTTP::Client.post(endpoint, headers: headers, body: body)
        unless response.status_code < 400
          STDERR.puts "[ocawe] telemetry export failed: HTTP #{response.status_code}"
        end
      rescue ex
        STDERR.puts "[ocawe] telemetry export failed: #{ex.message || ex.class.name}"
      end

      private def metrics_payload(points : Array(MetricPoint)) : String
        JSON.build do |json|
          json.object do
            json.field "resourceMetrics" do
              json.array do
                json.object do
                  write_resource(json)
                  json.field "scopeMetrics" do
                    json.array do
                      json.object do
                        write_scope(json)
                        json.field "metrics" do
                          json.array do
                            points.each { |point| write_metric(json, point) }
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end

      private def logs_payload(records : Array(LogRecord)) : String
        JSON.build do |json|
          json.object do
            json.field "resourceLogs" do
              json.array do
                json.object do
                  write_resource(json)
                  json.field "scopeLogs" do
                    json.array do
                      json.object do
                        write_scope(json)
                        json.field "logRecords" do
                          json.array do
                            records.each { |record| write_log_record(json, record) }
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end

      private def write_resource(json : JSON::Builder) : Nil
        json.field "resource" do
          json.object do
            json.field "attributes" do
              json.array do
                write_attr(json, "service.name", @config.service_name)
                write_attr(json, "service.version", @config.service_version)
              end
            end
          end
        end
      end

      private def write_scope(json : JSON::Builder) : Nil
        json.field "scope" do
          json.object do
            json.field "name", "ocawe"
            json.field "version", @config.service_version
          end
        end
      end

      private def write_metric(json : JSON::Builder, point : MetricPoint) : Nil
        json.object do
          json.field "name", point.name
          json.field "unit", point.unit
          json.field "sum" do
            json.object do
              json.field "aggregationTemporality", 2
              json.field "isMonotonic", point.kind == "counter"
              json.field "dataPoints" do
                json.array do
                  json.object do
                    json.field "timeUnixNano", point.time_unix_nano.to_s
                    write_attributes(json, point.attributes)
                    json.field "asDouble", point.value
                  end
                end
              end
            end
          end
        end
      end

      private def write_log_record(json : JSON::Builder, record : LogRecord) : Nil
        json.object do
          json.field "timeUnixNano", record.time_unix_nano.to_s
          json.field "severityText", record.severity.upcase
          json.field "body" do
            json.object { json.field "stringValue", record.body }
          end
          json.field "traceId", record.trace_id if record.trace_id
          json.field "spanId", record.span_id if record.span_id
          write_attributes(json, record.attributes)
        end
      end

      private def write_attributes(json : JSON::Builder, attributes : Hash(String, AttributeValue)) : Nil
        json.field "attributes" do
          json.array do
            attributes.each { |key, value| write_attr(json, key, value) }
          end
        end
      end

      private def write_attr(json : JSON::Builder, key : String, value : AttributeValue) : Nil
        json.object do
          json.field "key", key
          json.field "value" do
            json.object do
              case value
              when Bool
                json.field "boolValue", value
              when Int32, Int64
                json.field "intValue", value.to_s
              when Float32, Float64
                json.field "doubleValue", value.to_f
              else
                json.field "stringValue", value.to_s
              end
            end
          end
        end
      end
    end
  end
end
