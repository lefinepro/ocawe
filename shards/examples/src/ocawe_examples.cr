require "ocawe"
require "./custom_provider_example"
require "./control_flow_workflow_example"

module OcaweExamples
  VERSION = "0.1.0"
  EXAMPLES_ROOT = File.expand_path("..", __DIR__)

  def self.workflows_root : String
    EXAMPLES_ROOT
  end
end
