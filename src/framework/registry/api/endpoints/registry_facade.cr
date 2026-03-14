module Cogni
  module Registry
    extend self
    def node_kind(
      kind : String,
      &block : Cogni::Workflow::NodeContext, Cogni::Workflow::AnyHash -> Cogni::Workflow::NodeKindResult
    ) : Nil
      Cogni::RegistryApi.node_kind(kind, &block)
    end

    def resource(
      name : String,
      &block : Cogni::Workflow::NodeContext, Cogni::Workflow::AnyHash -> Cogni::Workflow::AnyHash
    ) : Nil
      Cogni::RegistryApi.resource(name, &block)
    end

    def workspace_schema(name : String, &block : Cogni::Workflow::AnyHash -> Nil) : Nil
      Cogni::RegistryApi.workspace_schema(name, &block)
    end

    def workspace_resolver(&block : Cogni::Workflow::AnyHash -> Cogni::Workflow::AnyHash) : Nil
      Cogni::RegistryApi.workspace_resolver(&block)
    end

    def workspace_hook(event : String, &block : Cogni::Workflow::NodeContext, Cogni::Workflow::AnyHash -> Nil) : Nil
      Cogni::RegistryApi.workspace_hook(event, &block)
    end
  end
end
