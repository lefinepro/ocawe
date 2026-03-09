require "json"

module Cogni
  class NodeKind
    getter node : String
    getter attributes : Cogni::Workflow::AnyHash

    def initialize(@node : String, @attributes : Cogni::Workflow::AnyHash = {} of String => JSON::Any)
      raise "node kind requires non-empty node" if @node.strip.empty?
    end
  end
end
