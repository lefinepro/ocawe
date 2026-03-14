module Cogni
  module ExampleConfig
    def self.settings : Cogni::Config::Settings
      Cogni::Config::Settings.new(
        workflows: Cogni::Config::WorkflowSettings.new(
          preferred_workflows_root: "./shards/examples/full-capabilities",
        ),
        node_kinds: Cogni::Config::NodeKindSettings.new(enabled: ["exec", "agent", "skill", "voice", "rag", "suspend", "control", "custom"]),
        functions: {
          "agent_opencode" => Cogni::Config::DefaultFunctionHandlers.agent_opencode,
          "agent_codex" => Cogni::Config::DefaultFunctionHandlers.agent_codex,
          "agent_cliproxy" => Cogni::Config::DefaultFunctionHandlers.agent_cliproxy,
          "agent_qwen" => Cogni::Config::DefaultFunctionHandlers.agent_qwen,
        } of String => Cogni::Workflow::FunctionHandler,
      )
    end
  end
end
