module Ocawe
  module Config
    module DefaultFunctionHandlers
      extend self

      def available : Hash(String, Ocawe::Workflow::FunctionHandler)
        handlers = {} of String => Ocawe::Workflow::FunctionHandler
        {% if Ocawe.has_constant?("AgentFunctionHandlers") %}
          handlers["agent_opencode"] = Ocawe::AgentFunctionHandlers.agent_opencode
          handlers["agent_codex"] = Ocawe::AgentFunctionHandlers.agent_codex
          handlers["agent_cliproxy"] = Ocawe::AgentFunctionHandlers.agent_cliproxy
          handlers["agent_claude_code"] = Ocawe::AgentFunctionHandlers.agent_claude_code
          handlers["agent_qwen"] = Ocawe::AgentFunctionHandlers.agent_qwen
        {% end %}
        handlers
      end
    end
  end
end
