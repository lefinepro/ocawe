module OcaweCore
  module AI
    struct ModelRef
      getter provider : String
      getter model : String

      def initialize(@provider : String, @model : String)
      end

      def self.parse(value : String) : ModelRef
        raw = value.strip
        raise "model must not be empty" if raw.empty?

        if slash = raw.index('/')
          provider = raw[0, slash].strip.downcase
          model = raw[slash + 1, raw.size - slash - 1].strip
          raise "invalid model provider: #{value}" if provider.empty?
          raise "invalid model name: #{value}" if model.empty?
          return new(provider, model)
        end

        new("openai", raw)
      end

      def to_s : String
        "#{@provider}/#{@model}"
      end
    end
  end
end
