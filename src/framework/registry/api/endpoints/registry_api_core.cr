module Ocawe
  module RegistryApi
    extend self

    alias AnyHash = Ocawe::Workflow::AnyHash
    alias Validator = Ocawe::Workflows::DSL::Validator
    alias WorkflowDefinition = Ocawe::Workflow::WorkflowDefinition
    alias WorkflowNode = Ocawe::Workflow::WorkflowNode
    alias WorkflowNodeResult = Ocawe::Workflow::WorkflowNodeResult
    alias NodeContext = Ocawe::Workflow::NodeContext
    alias NodeKind = Ocawe::Workflow::NodeKind
    @@bootstrap_actions = [] of Proc(Nil)
    @@capture_bootstrap_actions = true

    def reset_all! : Nil
      previous_capture = @@capture_bootstrap_actions
      @@capture_bootstrap_actions = false
      Ocawe::Workflow.reset_node_kind_registry!
      Ocawe::Workflow.reset_resource_registry!
      Ocawe::Workflow.reset_function_registry!
      Ocawe::Workflow.reset_workspace_registry!
      register_default_node_kinds!
      replay_bootstrap_actions!
      @@capture_bootstrap_actions = previous_capture
    end

    # Initialize the built-in node kinds without erasing handlers registered
    # by compiled workflow plugins before the HTTP app starts.
    def register_defaults! : Nil
      register_default_node_kinds!
      # Workflow plugins are loaded before the HTTP app starts, but the
      # workflow-cache rebuild can reset registries after that load. Replay is
      # idempotent: duplicate functions and node kinds are skipped by the
      # internal registration helpers, while missing plugin node kinds are
      # restored before the next workflow run.
      replay_bootstrap_actions!
    end

    def register_system_function(
      name : String,
      alias_name : String? = nil,
      &block : NodeContext -> Ocawe::Workflow::RunnableResult
    ) : String
      Ocawe::Workflow.register_system_function(name, alias_name: alias_name, &block)
    end

    def register_function(
      name : String,
      alias_name : String? = nil,
      source : Ocawe::Workflow::FunctionSource = Ocawe::Workflow::FunctionSource::User,
      &block : NodeContext -> Ocawe::Workflow::RunnableResult
    ) : String
      register_function_internal(name, alias_name: alias_name, source: source, persist: true, &block)
    end

    def call_function(name : String, ctx : NodeContext) : AnyHash
      Ocawe::Workflow.function_registry.call(name, ctx)
    end

    def node_kind(
      kind : String,
      &block : NodeContext, AnyHash -> Ocawe::Workflow::NodeKindResult
    ) : Nil
      register_node_kind_internal(kind, persist: true, &block)
    end

    def resource(
      name : String,
      &block : NodeContext, AnyHash -> AnyHash
    ) : Nil
      register_resource_internal(name, persist: true, &block)
    end

    def workspace_schema(name : String, &block : AnyHash -> Nil) : Nil
      register_workspace_schema_internal(name, persist: true, &block)
    end

    def workspace_resolver(&block : AnyHash -> AnyHash) : Nil
      register_workspace_resolver_internal(persist: true, &block)
    end

    def workspace_hook(event : String, &block : NodeContext, AnyHash -> Nil) : Nil
      register_workspace_hook_internal(event, persist: true, &block)
    end

    private def replay_bootstrap_actions! : Nil
      @@bootstrap_actions.each(&.call)
    end

    private def register_function_internal(
      name : String,
      alias_name : String? = nil,
      source : Ocawe::Workflow::FunctionSource = Ocawe::Workflow::FunctionSource::User,
      persist : Bool = false,
      &block : NodeContext -> Ocawe::Workflow::RunnableResult
    ) : String
      if !persist && Ocawe::Workflow.function_registry.registered?(name)
        return name
      end
      canonical = Ocawe::Workflow.register_function(name, alias_name: alias_name, source: source, &block)
      if persist && @@capture_bootstrap_actions
        handler = block
        @@bootstrap_actions << ->{
          register_function_internal(name, alias_name: alias_name, source: source, persist: false, &handler)
          nil
        }
      end
      canonical
    end

    private def register_node_kind_internal(
      kind : String,
      persist : Bool = false,
      &block : NodeContext, AnyHash -> Ocawe::Workflow::NodeKindResult
    ) : Nil
      return if !persist && Ocawe::Workflow.node_kind_registry.registered?(kind)
      Ocawe::Workflow.register_node_kind(kind, &block)
      if persist && @@capture_bootstrap_actions
        handler = block
        @@bootstrap_actions << ->{
          register_node_kind_internal(kind, persist: false, &handler)
          nil
        }
      end
    end

    private def register_resource_internal(
      name : String,
      persist : Bool = false,
      &block : NodeContext, AnyHash -> AnyHash
    ) : Nil
      Ocawe::Workflow.register_resource(name, &block)
      if persist && @@capture_bootstrap_actions
        handler = block
        @@bootstrap_actions << ->{
          register_resource_internal(name, persist: false, &handler)
          nil
        }
      end
    end

    private def register_workspace_schema_internal(
      name : String,
      persist : Bool = false,
      &block : AnyHash -> Nil
    ) : Nil
      Ocawe::Workflow.workspace_registry.register_schema(name, &block)
      if persist && @@capture_bootstrap_actions
        handler = block
        @@bootstrap_actions << ->{
          register_workspace_schema_internal(name, persist: false, &handler)
          nil
        }
      end
    end

    private def register_workspace_resolver_internal(
      persist : Bool = false,
      &block : AnyHash -> AnyHash
    ) : Nil
      Ocawe::Workflow.workspace_registry.register_resolver(&block)
      if persist && @@capture_bootstrap_actions
        handler = block
        @@bootstrap_actions << ->{
          register_workspace_resolver_internal(persist: false, &handler)
          nil
        }
      end
    end

    private def register_workspace_hook_internal(
      event : String,
      persist : Bool = false,
      &block : NodeContext, AnyHash -> Nil
    ) : Nil
      Ocawe::Workflow.workspace_registry.register_hook(event, &block)
      if persist && @@capture_bootstrap_actions
        handler = block
        @@bootstrap_actions << ->{
          register_workspace_hook_internal(event, persist: false, &handler)
          nil
        }
      end
    end

    private def register_default_node_kinds! : Nil
      node_kind("forgefed_subscribe") do |ctx, parameters|
        run_forgefed_subscribe_node(ctx, parameters)
      end
    end
  end
end
