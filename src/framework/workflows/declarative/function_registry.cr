module Cogni
  module Workflow
    enum FunctionSource
      System
      User
    end

    alias RunnableResult = AnyHash | AgentResult
    alias RunnableHandler = Proc(NodeContext, RunnableResult)
    alias FunctionHandler = RunnableHandler

    private struct RegisteredFunction
      getter canonical : String
      getter source : FunctionSource
      getter handler : RunnableHandler

      def initialize(@canonical : String, @source : FunctionSource, @handler : RunnableHandler)
      end
    end

    class FunctionRegistry
      def initialize
        @entries = [] of RegisteredFunction
        @lookup = {} of String => RegisteredFunction
        @user_collisions = Hash(String, Int32).new(0)
      end

      def reset! : Nil
        @entries.clear
        @lookup.clear
        @user_collisions.clear
      end

      def register(
        name : String,
        source : FunctionSource = FunctionSource::User,
        alias_name : String? = nil,
        &block : NodeContext -> RunnableResult
      ) : String
        base = normalize(name)
        raise "invalid function name: #{name}" if base.empty?

        if source == FunctionSource::System
          ensure_system_priority!(base)
        end

        canonical = resolve_canonical_name(base, source)
        handler : RunnableHandler = ->(ctx : NodeContext) : RunnableResult do
          block.call(ctx).as(RunnableResult)
        end
        register_entry(canonical, source, handler)

        if alias_name
          register_alias!(alias_name, canonical)
        end

        canonical
      end

      def register_alias(alias_name : String, target_name : String) : Nil
        target = resolve_entry(target_name)
        register_alias!(alias_name, target.canonical)
      end

      def call(name : String, ctx : NodeContext) : AnyHash
        result = resolve_entry(name).handler.call(ctx)
        case result
        when Hash(String, JSON::Any)
          result
        when AgentResult
          result.to_any_hash
        else
          raise "unsupported function result for #{name}"
        end
      end

      def registered?(name : String) : Bool
        @lookup.has_key?(normalize(name))
      end

      private def resolve_canonical_name(base : String, source : FunctionSource) : String
        if source == FunctionSource::System
          return base
        end

        if @lookup.has_key?(base)
          idx = (@user_collisions[base] += 1)
          "#{base}:#{idx}"
        else
          base
        end
      end

      private def ensure_system_priority!(base : String) : Nil
        existing = @lookup[base]?
        return unless existing
        return unless existing.source == FunctionSource::User

        idx = (@user_collisions[base] += 1)
        promoted = "#{base}:#{idx}"
        promoted_entry = RegisteredFunction.new(canonical: promoted, source: existing.source, handler: existing.handler)
        @entries << promoted_entry
        @lookup[normalize(promoted)] = promoted_entry
        @lookup.delete(base)
      end

      private def resolve_entry(name : String) : RegisteredFunction
        key = normalize(name)
        @lookup[key]? || raise "unknown function: #{name}"
      end

      private def register_entry(canonical : String, source : FunctionSource, handler : RunnableHandler) : Nil
        key = normalize(canonical)
        raise "function alias already registered: #{canonical}" if @lookup.has_key?(key)
        entry = RegisteredFunction.new(canonical: canonical, source: source, handler: handler)
        @entries << entry
        @lookup[key] = entry
      end

      private def register_alias!(alias_name : String, target_canonical : String) : Nil
        alias_key = normalize(alias_name)
        raise "invalid alias name: #{alias_name}" if alias_key.empty?
        raise "function alias already registered: #{alias_name}" if @lookup.has_key?(alias_key)
        target = resolve_entry(target_canonical)
        @lookup[alias_key] = target
      end

      private def normalize(value : String) : String
        value.strip.downcase
      end
    end

    @@function_registry = FunctionRegistry.new

    def self.function_registry : FunctionRegistry
      @@function_registry
    end

    def self.reset_function_registry! : Nil
      @@function_registry.reset!
    end

    def self.register_function(
      name : String,
      alias_name : String? = nil,
      source : FunctionSource = FunctionSource::User,
      &block : NodeContext -> RunnableResult
    ) : String
      @@function_registry.register(name, source: source, alias_name: alias_name, &block)
    end

    def self.register_system_function(
      name : String,
      alias_name : String? = nil,
      &block : NodeContext -> RunnableResult
    ) : String
      @@function_registry.register(name, source: FunctionSource::System, alias_name: alias_name, &block)
    end

    def self.register_function_alias(alias_name : String, target_name : String) : Nil
      @@function_registry.register_alias(alias_name, target_name)
    end
  end
end
