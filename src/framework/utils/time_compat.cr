module Ocawe
  module Utils
    module TimeCompat
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
