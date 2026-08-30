class ACD::Kemal::App
  def test_load_workflow_definition(
    bundle : ACD::Discovery::WorkflowBundle,
    loaded_agents : Array(ACD::Agents::LoadedAgent),
  ) : Ocawe::Workflow::WorkflowDefinition
    load_workflow_definition(bundle, loaded_agents)
  end

  def test_create_generated_workflow(
    request : ACD::Discovery::GeneratedWorkflowRequest,
  ) : ACD::Discovery::GeneratedWorkflowArtifact
    create_generated_workflow(request)
  end

  def test_delete_generated_workflow(
    workflow_id : String,
  ) : ACD::Discovery::GeneratedWorkflowDeletionArtifact
    delete_generated_workflow(workflow_id)
  end

  def test_generated_workflow_auth_error(env) : String?
    generated_workflow_auth_error(env)
  end

  def test_workflow_loaded?(workflow_id : String) : Bool
    !workflow_by_id(workflow_id).nil?
  end

  def test_copy_chat_identity_fields(
    source : Hash(String, JSON::Any),
    target : Hash(String, JSON::Any),
  ) : Nil
    copy_chat_identity_fields(source, target)
  end

  def test_workflow_chat_output(snapshot : Ocawe::Workflow::WorkflowRunSnapshot) : String
    workflow_chat_output(snapshot)
  end

  def test_workflow_chat_usage(snapshot : Ocawe::Workflow::WorkflowRunSnapshot) : Ocawe::Workflow::AnyHash?
    workflow_chat_usage(snapshot)
  end

  def test_workflow_chat_failure(snapshot : Ocawe::Workflow::WorkflowRunSnapshot) : String
    workflow_failure_message(snapshot.workflow_id, snapshot.status, snapshot.error)
  end

  def test_workflow_details_response(workflow_id : String) : String?
    workflow_details_response(workflow_id)
  end

  def test_generated_workflow_response(
    request : ACD::Discovery::GeneratedWorkflowRequest,
    artifact : ACD::Discovery::GeneratedWorkflowArtifact,
  ) : String
    generated_workflow_response(request, artifact)
  end

  def test_wrap_nodes_in_control(
    nodes : Array(Ocawe::Workflow::WorkflowNode),
    name : String,
  ) : Ocawe::Workflow::WorkflowNode
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

  def test_set_workflow_ids(ids : Array(String)) : Nil
    @cache_lock.synchronize do
      @workflow_ids = ids.dup
    end
  end

  def test_set_workflow_federation_resource(
    workflow_id : String,
    id : String = "proxy",
    name : String = "proxy",
    description : String = "",
    action : String = "deliverService",
    purpose : String = "request",
    tags : Array(String) = [] of String,
  ) : Nil
    @cache_lock.synchronize do
      @workflow_federation_resources[workflow_id] = [{
        id:          id,
        name:        name,
        description: description,
        action:      action,
        purpose:     purpose,
        tags:        tags,
      }]
    end
  end

  def test_resolve_ticket_workflow_actor(
    body : Hash(String, JSON::Any),
    ticket : Hash(String, JSON::Any),
    local_domain : String,
    default_actor : String = "",
  ) : String
    resolve_ticket_workflow_actor(body, ticket, local_domain, default_actor)
  end

  def test_local_actor_document(workflow_id : String) : Hash(String, JSON::Any)
    local_workflow_actor_document(aptok_federation.create_context, workflow_id)
  end

  def test_extract_ticket_activity_payload(
    activity : Hash(String, JSON::Any),
  ) : NamedTuple(activity_type: String, ticket: Hash(String, JSON::Any))?
    extract_ticket_activity_payload(activity)
  end

  def test_infer_ticket_workflow_activity(
    activity_doc : Hash(String, JSON::Any),
    ticket : Hash(String, JSON::Any),
    incoming_activity_type : String,
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
    result_text : String,
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
  ) : Nil
    publish_result_activity_from_output(
      workflow_id: workflow_id,
      run_id: run_id,
      run_status: run_status,
      output: output,
      ticket: ticket,
      requested_activity: requested_activity,
      remote_actor: remote_actor,
      workflow_actor: workflow_actor,
      local_domain: local_domain,
      published_at: published_at,
    )
  end

  def test_list_outbox_events : Array(Hash(String, JSON::Any))
    events = [] of Hash(String, JSON::Any)
    @federation_kv.list("ocawe:federation:outbox:").each do |entry|
      activity = JSON.parse(entry.value).as_h
      events << {"activity" => JSON.parse(activity.to_json)} of String => JSON::Any
    end
    events
  end

  def test_federation_metadata_document : Hash(String, JSON::Any)
    federation_metadata_document
  end

  def test_ensure_aptok_subscription(value : String) : Hash(String, JSON::Any)
    ensure_aptok_subscription(value)
  end

  def test_verify_webhook_signature(payload : String, headers : ::HTTP::Headers) : Bool
    verify_webhook_signature(payload, headers)
  end

  def test_select_webhook_workflow_id(requested : String?, workflow_ids : Array(String)) : String
    select_webhook_workflow_id(requested, workflow_ids)
  end

  def test_handle_cawfile_webhook(
    body : Hash(String, JSON::Any),
    headers : ::HTTP::Headers,
    workflow_override : String? = nil,
  ) : Hash(String, JSON::Any)
    handle_cawfile_webhook(body, headers, workflow_override)
  end
end
