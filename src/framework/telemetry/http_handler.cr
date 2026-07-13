require "kemal"
require "../telemetry"
require "../utils/time_compat"

module Ocawe
  module Telemetry
    class HTTPHandler < ::Kemal::Handler
      def call(env : HTTP::Server::Context)
        return call_next(env) unless Telemetry.enabled?

        started = Ocawe::Utils::TimeCompat.monotonic
        method = env.request.method
        path = env.request.path
        Telemetry.apply_traceparent(env.request.headers["traceparent"]?)
        attrs = {
          "http.request.method" => method,
          "url.path"            => path,
          "server.address"      => env.request.headers["Host"]?.to_s,
          "user_agent.original" => env.request.headers["User-Agent"]?.to_s,
        } of String => AttributeValue
        span = Telemetry.start_span("HTTP #{method} #{path}", attrs, "server")
        if traceparent = Telemetry.traceparent
          env.response.headers["traceparent"] = traceparent
        end

        exception = nil.as(Exception?)
        begin
          call_next(env)
        rescue ex
          exception = ex
          raise ex
        ensure
          route = route_path(env) || path
          status_code = env.response.status_code
          duration_ms = Ocawe::Utils::TimeCompat.elapsed_milliseconds(started)
          status = status_code >= 500 || exception ? "error" : "success"
          final_attrs = {
            "http.route"                => route,
            "http.response.status_code" => status_code,
            "http.server.duration_ms"   => duration_ms,
          } of String => AttributeValue
          Telemetry.finish_span(span, status: status, error: exception.try(&.message), attributes: final_attrs)

          metric_attrs = {
            "http.request.method"       => method,
            "http.route"                => route,
            "http.response.status_code" => status_code,
          } of String => AttributeValue
          Telemetry.increment("http.server.request.count", attributes: metric_attrs)
          Telemetry.histogram("http.server.request.duration_ms", duration_ms, "ms", metric_attrs)
          if status_code >= 500 || exception
            Telemetry.increment("http.server.request.errors", attributes: metric_attrs)
            Telemetry.log(
              "error",
              exception.try(&.message) || "HTTP #{status_code}",
              metric_attrs.merge({"event.name" => "http.server.error"} of String => AttributeValue)
            )
          end
        end
      end

      private def route_path(env : HTTP::Server::Context) : String?
        env.route_found? ? env.route.path : nil
      rescue
        nil
      end
    end
  end
end
