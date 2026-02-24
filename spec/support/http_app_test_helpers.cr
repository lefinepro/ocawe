class ACD::HTTP::App
  def test_load_workflow_definition(
    bundle : ACD::Discovery::WorkflowBundle,
    loaded_agents : Array(ACD::Agents::LoadedAgent)
  ) : Cogni::Workflow::WorkflowDefinition
    load_workflow_definition(bundle, loaded_agents)
  end

  def test_wrap_nodes_in_control(
    nodes : Array(Cogni::Workflow::WorkflowNode),
    name : String
  ) : Cogni::Workflow::WorkflowNode
    wrap_nodes_in_control(nodes, name)
  end

  def test_register_configured_functions! : Nil
    register_configured_functions!
  end
end
