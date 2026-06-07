module Ocawe
  module ExampleConfig
    def self.settings : Ocawe::Config::Settings
      Ocawe::Config::Settings.new(
        workflows: Ocawe::Config::WorkflowSettings.new(
          preferred_workflows_root: "./shards/examples/full-capabilities",
        ),
        node_kinds: Ocawe::Config::NodeKindSettings.new(enabled: ["exec", "agent", "skill", "voice", "rag", "suspend", "control", "custom"]),
        functions: {
          "agent_opencode" => Ocawe::Config::DefaultFunctionHandlers.agent_opencode,
          "agent_codex" => Ocawe::Config::DefaultFunctionHandlers.agent_codex,
          "agent_cliproxy" => Ocawe::Config::DefaultFunctionHandlers.agent_cliproxy,
          "agent_qwen" => Ocawe::Config::DefaultFunctionHandlers.agent_qwen,
        } of String => Ocawe::Workflow::FunctionHandler,
      )
    end
  end
end
