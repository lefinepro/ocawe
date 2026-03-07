# Licensed under MIT License
#
# Syntax:
#   # Comments (Ruby-style)
#   key = "value"
#   number = 12345
#   enabled = true
#   array = [1, 2, 3]
#
#   block do
#     nested = "value"
#   end
#
# Usage:
#   require "rcl"
#
#   doc = RCL.parse_file("config.rcl")
#   doc.get_string("block/nested")
#
#   # Register custom block handlers
#   RCL::Blocks.register("server") do |block|
#     {:ok, {address: block["address"]}.named_tuple}
#   end

require "./rcl/version"
require "./rcl/token"
require "./rcl/ast"
require "./rcl/lexer"
require "./rcl/parser"
require "./rcl/document"
require "./rcl/formatter"
require "./rcl/converters"
require "./rcl/blocks"

module RCL
  # Parse RCL file and return Document
  def self.parse(path : String) : Document
    parse_file(path)
  end

  # Parse RCL file and return Document
  def self.parse_file(path : String) : Document
    content = File.read(path)
    parse_string(content)
  end

  # Parse RCL string and return Document
  def self.parse_string(content : String) : Document
    RCL::Parser.parse(content)
  end

  # Parse and convert to Hash
  def self.parse_file_to_h(path : String) : Hash(String, RCL::Value)
    parse_file(path).to_h
  end

  # Parse string and convert to Hash
  def self.parse_string_to_h(content : String) : Hash(String, RCL::Value)
    parse_string(content).to_h
  end

  # Format parsed document into canonical RCL source text
  def self.format(document : Document) : String
    RCL::Formatter.format(document)
  end

  def self.to_yaml(document : Document) : String
    RCL::Converters.to_yaml(document.to_value)
  end

  def self.to_toml(document : Document) : String
    RCL::Converters.to_toml(document.to_value)
  end

  def self.to_hcl(document : Document) : String
    RCL::Converters.to_hcl(document.to_value)
  end

  def self.parse_string_to_yaml(content : String) : String
    to_yaml(parse_string(content))
  end

  def self.parse_string_to_toml(content : String) : String
    to_toml(parse_string(content))
  end

  def self.parse_string_to_hcl(content : String) : String
    to_hcl(parse_string(content))
  end
end
