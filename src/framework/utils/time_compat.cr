module Ocawe
  module Utils
    module TimeCompat
      # The type `.monotonic` returns, so callers can annotate variables
      # (e.g. `nil.as(TimeCompat::Instant?)`) without naming either spelling.
      {% if compare_versions(Crystal::VERSION, "1.19.0") >= 0 %}
        alias Instant = Time::Instant
      {% else %}
        alias Instant = Time::Span
      {% end %}

      def self.monotonic
        {% if compare_versions(Crystal::VERSION, "1.19.0") >= 0 %}
          Time.instant
        {% else %}
          Time.monotonic
        {% end %}
      end

      def self.elapsed_milliseconds(start) : Float64
        (monotonic - start).total_milliseconds
      end
    end
  end
end
