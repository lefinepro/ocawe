module Ocawe
  module Config
    module DefaultFunctionHandlers
      extend self

      def available : Hash(String, Ocawe::Workflow::FunctionHandler)
        handlers = {} of String => Ocawe::Workflow::FunctionHandler
        handlers
      end
    end
  end
end
