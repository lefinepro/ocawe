require "./spec_helper"

describe "OpenAI chat completion identity fields" do
  it "copies caller identity fields into workflow input data" do
    app = ACD::Kemal::App.new(0)
    source = {
      "user_actor"  => json_str("https://lefine.pro/actors/alice"),
      "user_handle" => json_str("@alice@lefine.pro"),
      "model"       => json_str("workflow/orator"),
    } of String => JSON::Any
    target = {
      "prompt" => json_str("#plan make a todo app"),
    } of String => JSON::Any

    app.test_copy_chat_identity_fields(source, target)

    target["user_actor"].as_s.should eq("https://lefine.pro/actors/alice")
    target["user_handle"].as_s.should eq("@alice@lefine.pro")
    target.has_key?("model").should eq(false)
  end

  it "skips empty identity fields" do
    app = ACD::Kemal::App.new(0)
    source = {
      "user_actor"  => json_str("   "),
      "user_handle" => json_str(""),
    } of String => JSON::Any
    target = {} of String => JSON::Any

    app.test_copy_chat_identity_fields(source, target)

    target.empty?.should eq(true)
  end

  it "extracts Orator last_response as chat completion content" do
    app = ACD::Kemal::App.new(0)
    snapshot = Ocawe::Workflow::WorkflowRunSnapshot.new(
      workflow_id: "orator",
      run_id: "run-1",
      status: "success",
      state: {"last_response" => json_str("The final answer")} of String => JSON::Any,
      output: nil,
      init_data: nil,
      node_results: nil,
      node_index: 1,
      resume_labels: nil,
      suspend_payload: nil,
      error: nil,
      resource_id: nil,
      updated_at: "2026-08-11T00:00:00Z",
    )

    app.test_workflow_chat_output(snapshot).should eq("The final answer")
  end

  it "preserves Orator marketplace cost in OpenAI-compatible usage" do
    app = ACD::Kemal::App.new(0)
    usage = {
      "prompt_tokens"     => JSON.parse("10"),
      "completion_tokens" => JSON.parse("5"),
      "total_tokens"      => JSON.parse("15"),
      "cost"              => JSON.parse("0.300015"),
      "currency"          => json_str("USD"),
    } of String => JSON::Any
    snapshot = Ocawe::Workflow::WorkflowRunSnapshot.new(
      workflow_id: "orator",
      run_id: "run-price",
      status: "success",
      state: {"content" => json_str("The priced answer"), "usage" => JSON.parse(usage.to_json)} of String => JSON::Any,
      output: nil,
      init_data: nil,
      node_results: nil,
      node_index: 1,
      resume_labels: nil,
      suspend_payload: nil,
      error: nil,
      resource_id: nil,
      updated_at: "2026-08-13T00:00:00Z",
    )

    extracted = app.test_workflow_chat_usage(snapshot).not_nil!
    extracted["cost"].as_f.should eq(0.300015)
    extracted["currency"].as_s.should eq("USD")
  end

  it "describes failed Orator runs as errors instead of answer content" do
    app = ACD::Kemal::App.new(0)
    snapshot = Ocawe::Workflow::WorkflowRunSnapshot.new(
      workflow_id: "orator",
      run_id: "run-2",
      status: "failed",
      state: {"workflow_id" => json_str("orator")} of String => JSON::Any,
      output: nil,
      init_data: nil,
      node_results: nil,
      node_index: 0,
      resume_labels: nil,
      suspend_payload: nil,
      error: Ocawe::Workflow::WorkflowError.new("node_error", "provider returned HTTP 401"),
      resource_id: nil,
      updated_at: "2026-08-11T00:00:00Z",
    )

    app.test_workflow_chat_failure(snapshot).should eq("workflow orator failed: provider returned HTTP 401")
  end
end
