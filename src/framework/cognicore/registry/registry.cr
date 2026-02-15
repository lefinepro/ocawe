module CogniCore
  module Registry
    WORKFLOW_BUNDLES = [] of NamedTuple(id: String, source_root_type: String, root_path: String, workflow_file: String, agents_dir: String, skills_dir: String, agent_count: Int32, skill_count: Int32, agent_node_count: Int32, skill_node_count: Int32, tool_count: Int32, custom_count: Int32, approve_count: Int32)
  end
end
