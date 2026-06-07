module Ocawe
  module Registry
    extend self
    def node_kind(
      kind : String,
      &block : Ocawe::Workflow::NodeContext, Ocawe::Workflow::AnyHash -> Ocawe::Workflow::NodeKindResult
    ) : Nil
      Ocawe::RegistryApi.node_kind(kind, &block)
    end

    def resource(
      name : String,
      &block : Ocawe::Workflow::NodeContext, Ocawe::Workflow::AnyHash -> Ocawe::Workflow::AnyHash
    ) : Nil
      Ocawe::RegistryApi.resource(name, &block)
    end

    def workspace_schema(name : String, &block : Ocawe::Workflow::AnyHash -> Nil) : Nil
      Ocawe::RegistryApi.workspace_schema(name, &block)
    end

    def workspace_resolver(&block : Ocawe::Workflow::AnyHash -> Ocawe::Workflow::AnyHash) : Nil
      Ocawe::RegistryApi.workspace_resolver(&block)
    end

    def workspace_hook(event : String, &block : Ocawe::Workflow::NodeContext, Ocawe::Workflow::AnyHash -> Nil) : Nil
      Ocawe::RegistryApi.workspace_hook(event, &block)
    end
  end
end
