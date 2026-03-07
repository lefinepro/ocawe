module Cogni
  module Config
    module DefaultFunctionHandlers
      extend self

      def available : Hash(String, Cogni::Workflow::FunctionHandler)
        handlers = {} of String => Cogni::Workflow::FunctionHandler
        {% if Cogni.has_constant?("AgentFunctionHandlers") %}
          handlers["agent_opencode"] = Cogni::AgentFunctionHandlers.agent_opencode
          handlers["agent_codex"] = Cogni::AgentFunctionHandlers.agent_codex
          handlers["agent_cliproxy"] = Cogni::AgentFunctionHandlers.agent_cliproxy
          handlers["agent_claude_code"] = Cogni::AgentFunctionHandlers.agent_claude_code
          handlers["agent_qwen"] = Cogni::AgentFunctionHandlers.agent_qwen
        {% end %}
        handlers
      end
    end
  end
end
