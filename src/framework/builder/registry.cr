require "./builder"
require "./runtime"
require "./static_builder"
require "./alpine_builder"
require "./nixos_builder"

module Ocawe
  module Builder
    class BuilderRegistry
      def initialize
        @builders = {} of String => Builder
        register(StaticBuilder.new)
        register(AlpineBuilder.new)
        register(NixOSBuilder.new)
      end

      def register(builder : Builder) : Nil
        @builders[builder.base] = builder
      end

      def resolve(base : String) : Builder
        @builders[base]? || raise "unsupported container base: #{base}"
      end

      def reset! : Nil
        @builders.clear
        register(StaticBuilder.new)
        register(AlpineBuilder.new)
        register(NixOSBuilder.new)
      end
    end

    @@builder_registry = BuilderRegistry.new

    def self.builder_registry : BuilderRegistry
      @@builder_registry
    end

    def self.reset_builder_registry! : Nil
      @@builder_registry.reset!
    end
  end
end
