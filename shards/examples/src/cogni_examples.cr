require "cogni"

module CogniExamples
  VERSION = "0.1.0"
  EXAMPLES_ROOT = File.expand_path("..", __DIR__)

  def self.workflows_root : String
    EXAMPLES_ROOT
  end
end
