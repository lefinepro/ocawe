require "option_parser"
require "./framework/cognicore/version"
require "./framework/cognicore/schema/types"
require "./framework/cognicore/schema/crystal_dsl"
require "./framework/cognicore/workflow/run"
require "./framework/http/app"

module CogniCore
  DEFAULT_PORT = 4111

  def self.run
    load_dotenv

    port = DEFAULT_PORT
    workflows_root = nil.as(String?)
    fallback_workflows_root = nil.as(String?)

    OptionParser.parse do |parser|
      parser.banner = "Usage: cognicore [arguments]"
      parser.on("-p PORT", "--port=PORT", "HTTP port") { |value| port = value.to_i }
      parser.on("--workflows-root=PATH", "Preferred workflows root path") { |value| workflows_root = value }
      parser.on("--fallback-workflows-root=PATH", "Fallback workflows root path") { |value| fallback_workflows_root = value }
      parser.on("-v", "--version", "Print version") do
        puts VERSION
        exit(0)
      end
      parser.on("-h", "--help", "Show help") do
        puts parser
        exit(0)
      end
    end

    ACD::HTTP::App.new(port, workflows_root: workflows_root, fallback_workflows_root: fallback_workflows_root).start
  end

  private def self.load_dotenv(path : String = ".env") : Nil
    return unless File.exists?(path)

    File.each_line(path) do |line|
      raw = line.strip
      next if raw.empty? || raw.starts_with?("#")

      eq_index = raw.index('=')
      next unless eq_index

      key = raw[0, eq_index].strip
      value = raw[eq_index + 1, raw.size - eq_index - 1].strip
      next if key.empty? || ENV.has_key?(key)

      if value.starts_with?('"') && value.ends_with?('"') && value.size >= 2
        value = value[1, value.size - 2]
      elsif value.starts_with?('\'') && value.ends_with?('\'') && value.size >= 2
        value = value[1, value.size - 2]
      end

      ENV[key] = value
    end
  end
end
