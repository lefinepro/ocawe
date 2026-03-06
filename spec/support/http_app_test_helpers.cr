class ACD::Kemal::App
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

  def test_federation_actor_from_node(node : JSON::Any?) : String
    federation_actor_from_node(node)
  end

  def test_workflow_id_from_actor(actor : String) : String
    workflow_id_from_actor(actor)
  end

  def test_resolve_ticket_workflow_actor(
    body : Hash(String, JSON::Any),
    ticket : Hash(String, JSON::Any),
    local_domain : String
  ) : String
    resolve_ticket_workflow_actor(body, ticket, local_domain)
  end
end
