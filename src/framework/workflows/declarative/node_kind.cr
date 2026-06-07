require "json"

module Ocawe
  class NodeKind
    getter node : String
    getter attributes : Ocawe::Workflow::AnyHash

    def initialize(@node : String, @attributes : Ocawe::Workflow::AnyHash = {} of String => JSON::Any)
      raise "node kind requires non-empty node" if @node.strip.empty?
    end
  end
end
