require "json"

module Cogni
  class NodeKind
    getter node : String
    getter parameters : Cogni::Workflow::AnyHash

    def initialize(@node : String, @parameters : Cogni::Workflow::AnyHash = {} of String => JSON::Any)
      raise "node kind requires non-empty node" if @node.strip.empty?
    end
  end
end
