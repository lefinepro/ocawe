module Ocawe
  # Public registration facade for application commands.
  #
  # Commands use the existing function registry and bootstrap lifecycle.  The
  # facade gives Cawfile plugins a stable API without creating a second
  # execution or state model.
  module Command
    extend self

    @@names = [] of String

    def register(name : String, handler : Ocawe::Workflow::RunnableHandler) : String
      normalized = name.strip.downcase
      raise "invalid command name: #{name}" if normalized.empty?
      raise "command already registered: #{name}" if Ocawe::Workflow.function_registry.registered?(normalized)

      canonical = Ocawe::RegistryApi.register_function(normalized, &handler)
      @@names << normalized unless @@names.includes?(normalized)
      canonical
    end

    def names : Array(String)
      @@names.sort
    end
  end
end

# Keep the short form available to Cawfiles and command plugins.
Command = Ocawe::Command
