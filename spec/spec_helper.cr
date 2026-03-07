require "json"
require "spec"
require "../src/cogni"
require "./support/http_app_test_helpers"
require "./support/agent_functions_test_helpers"

module SpecHelpers
  def self.json_any(value)
    JSON.parse(value.to_json)
  end

  def self.json_bool(v : Bool)
    JSON.parse(v.to_json)
  end

  def self.json_str(v : String)
    JSON.parse(v.to_json)
  end
end

def json_any(value)
  SpecHelpers.json_any(value)
end

def json_bool(v : Bool)
  SpecHelpers.json_bool(v)
end

def json_str(v : String)
  SpecHelpers.json_str(v)
end
