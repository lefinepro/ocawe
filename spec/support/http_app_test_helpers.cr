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

  def test_dataset_service : Cogni::Dataset::Service
    @dataset_service
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

  def test_set_workflow_ids(ids : Array(String)) : Nil
    @cache_lock.synchronize do
      @workflow_ids = ids.dup
    end
  end

  def test_resolve_ticket_workflow_actor(
    body : Hash(String, JSON::Any),
    ticket : Hash(String, JSON::Any),
    local_domain : String,
    default_actor : String = ""
  ) : String
    resolve_ticket_workflow_actor(body, ticket, local_domain, default_actor)
  end

  def test_local_actor_document(workflow_id : String) : Hash(String, JSON::Any)
    local_actor_document(workflow_id)
  end

  def test_extract_ticket_activity_payload(
    activity : Hash(String, JSON::Any)
  ) : NamedTuple(activity_type: String, ticket: Hash(String, JSON::Any))?
    extract_ticket_activity_payload(activity)
  end

  def test_infer_ticket_workflow_activity(
    activity_doc : Hash(String, JSON::Any),
    ticket : Hash(String, JSON::Any),
    incoming_activity_type : String
  ) : String
    infer_ticket_workflow_activity(activity_doc, ticket, incoming_activity_type)
  end

  def test_build_merge_result_offer_activity(
    suffix : String,
    ticket : Hash(String, JSON::Any),
    output : Hash(String, JSON::Any),
    remote_actor : String,
    workflow_actor : String,
    local_domain : String,
    result_text : String
  ) : Hash(String, JSON::Any)
    build_merge_result_offer_activity(
      suffix: suffix,
      ticket: ticket,
      output: output,
      remote_actor: remote_actor,
      workflow_actor: workflow_actor,
      local_domain: local_domain,
      result_text: result_text,
    )
  end

  def test_publish_result_activity_from_output(
    workflow_id : String,
    run_id : String,
    run_status : String,
    output : Hash(String, JSON::Any),
    ticket : Hash(String, JSON::Any),
    requested_activity : String,
    remote_actor : String,
    workflow_actor : String,
    local_domain : String,
    published_at : String,
    local_actor : String = ""
  ) : Nil
    publish_result_activity_from_output(
      workflow_id: workflow_id,
      run_id: run_id,
      run_status: run_status,
      output: output,
      ticket: ticket,
      requested_activity: requested_activity,
      remote_actor: remote_actor,
      local_actor: local_actor,
      workflow_actor: workflow_actor,
      local_domain: local_domain,
      published_at: published_at,
    )
  end

  def test_list_outbox_events : Array(Hash(String, JSON::Any))
    @federation_store.list_outbox_events
  end

  def test_extract_activities_from_outbox(
    outbox_doc : Hash(String, JSON::Any)
  ) : Array(Hash(String, JSON::Any))
    extract_activities_from_outbox(outbox_doc)
  end

  def test_validate_contextual_federation_object(
    body : Hash(String, JSON::Any),
    expected_kind : String = "object"
  ) : String?
    validate_contextual_federation_object(body, expected_kind)
  end
end
