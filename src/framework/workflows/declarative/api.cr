module Cogni
  class Workflow < Cogni::Workflows::Declarative::WorkflowDefinition
    def self.build(id : String, description : String? = nil) : self
      new(id, description)
    end
  end
end
