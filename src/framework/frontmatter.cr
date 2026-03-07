require "yaml"

module ACD
  module Frontmatter
    class ParseError < Exception
    end

    struct ParsedDocument
      getter data : Hash(String, YAML::Any)
      getter body : String

      def initialize(@data : Hash(String, YAML::Any), @body : String)
      end
    end

    def self.parse_markdown(content : String, path : String) : ParsedDocument
      match = content.match(/\A---\s*\n(.*?)\n---\s*\n/m)
      raise ParseError.new("#{path}: missing YAML frontmatter") unless match

      yaml_raw = match[1]
      body = content.sub(match[0], "").strip
      parsed = YAML.parse(yaml_raw).as_h?
      raise ParseError.new("#{path}: frontmatter must be a YAML object") unless parsed

      data = {} of String => YAML::Any
      parsed.each { |k, v| data[k.to_s] = v }

      ParsedDocument.new(data, body)
    rescue ex : YAML::ParseException
      raise ParseError.new("#{path}: invalid YAML frontmatter: #{ex.message}")
    end
  end
end
