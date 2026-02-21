module Cogni
  module Workflow
    def self.build(id : String, description : String? = nil) : WorkflowDefinition
      WorkflowDefinition.new(id, description)
    end
  end
end
