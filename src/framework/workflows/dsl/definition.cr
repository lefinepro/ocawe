module Cogni
  module Workflows
    module DSL
    struct WorkflowBundleDefinition
      include JSON::Serializable

      getter id : String
      getter source_root_type : String
      getter root_path : String
      getter workflow_file : String
      getter agents_dir : String
      getter skills_dir : String
      getter agent_count : Int32
      getter skill_count : Int32
      getter agent_node_count : Int32
      getter skill_node_count : Int32
      getter tool_count : Int32
      getter fn_count : Int32
      getter suspend_count : Int32
    end
  end
  end
end
