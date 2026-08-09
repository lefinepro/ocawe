module Ocawe
  # Public application-facing registration facade for local workflow commands.
  module Command
    extend self

    # Registers a command in the existing function registry and bootstrap
    # lifecycle. Command names are intentionally stricter than the legacy
    # RegistryApi.register_function entry point because bare workflow calls
    # must resolve to one command deterministically.
    def register(name : String, handler : Ocawe::Workflow::RunnableHandler) : String
      normalized = name.strip.downcase
      raise "invalid command name: #{name}" if normalized.empty?
      raise "command already registered: #{name}" if Ocawe::Workflow.function_registry.registered?(name)

      Ocawe::RegistryApi.register_function(name, &handler)
    end
  end
end

# Cawfiles and files under plugins/commands use the short public form from the
# Commands API brief without requiring an application-local compatibility shim.
Command = Ocawe::Command
