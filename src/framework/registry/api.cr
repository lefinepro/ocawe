module Cogni
  module Registry
    extend self

    def node_kind(
      kind : String,
      &block : Cogni::Workflows::Declarative::NodeContext, Cogni::Workflows::Declarative::AnyHash -> Cogni::Workflows::Declarative::NodeKindResult
    ) : Nil
      Cogni::Workflows::Declarative.register_node_kind(kind, &block)
    end

    def resource(
      name : String,
      &block : Cogni::Workflows::Declarative::NodeContext, Cogni::Workflows::Declarative::AnyHash -> Cogni::Workflows::Declarative::AnyHash
    ) : Nil
      Cogni::Workflows::Declarative.register_resource(name, &block)
    end
  end
end
