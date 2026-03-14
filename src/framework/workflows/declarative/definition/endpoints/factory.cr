module Cogni
  module Workflow
    def self.create_workflow(id : String, description : String? = nil)
      WorkflowDefinition.new(id, description)
    end
  end
end
