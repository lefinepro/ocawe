module Cogni
  module RegistryApi
    extend self

    alias AnyHash = Cogni::Workflow::AnyHash
    alias Validator = Cogni::Workflows::DSL::Validator
    alias WorkflowDefinition = Cogni::Workflow::WorkflowDefinition
    alias WorkflowNode = Cogni::Workflow::WorkflowNode
    alias WorkflowNodeResult = Cogni::Workflow::WorkflowNodeResult
    alias NodeContext = Cogni::Workflow::NodeContext
    alias NodeKind = Cogni::Workflow::NodeKind
    @@bootstrap_actions = [] of Proc(Nil)
    @@capture_bootstrap_actions = true

    def reset_all! : Nil
      previous_capture = @@capture_bootstrap_actions
      @@capture_bootstrap_actions = false
      Cogni::Workflow.reset_node_kind_registry!
      Cogni::Workflow.reset_resource_registry!
      Cogni::Workflow.reset_function_registry!
      Cogni::Workflow.reset_workspace_registry!
      register_default_node_kinds!
      replay_bootstrap_actions!
      @@capture_bootstrap_actions = previous_capture
    end

    def register_system_function(
      name : String,
      alias_name : String? = nil,
      &block : NodeContext -> Cogni::Workflow::RunnableResult
    ) : String
      Cogni::Workflow.register_system_function(name, alias_name: alias_name, &block)
    end

    def register_function(
      name : String,
      alias_name : String? = nil,
      source : Cogni::Workflow::FunctionSource = Cogni::Workflow::FunctionSource::User,
      &block : NodeContext -> Cogni::Workflow::RunnableResult
    ) : String
      register_function_internal(name, alias_name: alias_name, source: source, persist: true, &block)
    end

    def call_function(name : String, ctx : NodeContext) : AnyHash
      Cogni::Workflow.function_registry.call(name, ctx)
    end

    def node_kind(
      kind : String,
      &block : NodeContext, AnyHash -> Cogni::Workflow::NodeKindResult
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
      source : Cogni::Workflow::FunctionSource = Cogni::Workflow::FunctionSource::User,
      persist : Bool = false,
      &block : NodeContext -> Cogni::Workflow::RunnableResult
    ) : String
      canonical = Cogni::Workflow.register_function(name, alias_name: alias_name, source: source, &block)
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
      &block : NodeContext, AnyHash -> Cogni::Workflow::NodeKindResult
    ) : Nil
      Cogni::Workflow.register_node_kind(kind, &block)
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
      Cogni::Workflow.register_resource(name, &block)
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
      Cogni::Workflow.workspace_registry.register_schema(name, &block)
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
      Cogni::Workflow.workspace_registry.register_resolver(&block)
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
      Cogni::Workflow.workspace_registry.register_hook(event, &block)
      if persist && @@capture_bootstrap_actions
        handler = block
        @@bootstrap_actions << ->{
          register_workspace_hook_internal(event, persist: false, &handler)
          nil
        }
      end
    end

    private def register_default_node_kinds! : Nil
      node_kind("agent_codex") do |ctx, _parameters|
        call_function("agent_codex", ctx)
      end
      node_kind("agent_cliproxy") do |ctx, _parameters|
        call_function("agent_cliproxy", ctx)
      end
      node_kind("agent_opencode") do |ctx, _parameters|
        call_function("agent_opencode", ctx)
      end
      node_kind("agent_claude_code") do |ctx, _parameters|
        call_function("agent_claude_code", ctx)
      end
      node_kind("agent_qwen") do |ctx, _parameters|
        call_function("agent_qwen", ctx)
      end
      node_kind("forgefed_subscribe") do |ctx, parameters|
        run_forgefed_subscribe_node(ctx, parameters)
      end
    end
  end
end
