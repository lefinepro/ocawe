module CogniCore
  module Utils
    module ConfigParser
      # Parses a key=value assignment line, handling quoted values
      def self.parse_assignment(line : String) : Tuple(String?, String)
        parts = line.split("=", 2)
        return {nil, ""} if parts.size < 2
        key = parts[0].strip
        raw = parts[1].strip
        value = unquote_value(raw)
        {key, value}
      end

      # Removes quotes from a string value if present
      def self.unquote_value(value : String) : String
        raw = value
        if raw.starts_with?('"') && raw.ends_with?('"') && raw.size >= 2
          return raw[1, raw.size - 2]
        elsif raw.starts_with?('\'') && raw.ends_with?('\'') && raw.size >= 2
          return raw[1, raw.size - 2]
        end
        raw
      end

      # Loads environment variables from a .env file
      def self.load_dotenv(path : String = ".env") : Nil
        return unless File.exists?(path)

        File.each_line(path) do |line|
          raw = line.strip
          next if raw.empty? || raw.starts_with?("#")

          eq_index = raw.index('=')
          next unless eq_index

          key = raw[0, eq_index].strip
          value = raw[eq_index + 1, raw.size - eq_index - 1].strip
          next if key.empty? || ENV.has_key?(key)

          ENV[key] = unquote_value(value)
        end
      end
    end
  end
end