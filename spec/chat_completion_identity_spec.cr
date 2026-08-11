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
end
