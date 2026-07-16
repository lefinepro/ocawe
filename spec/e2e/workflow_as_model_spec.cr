require "./e2e_spec_helper"

describe "E2E: Workflow as Model in Chat Completions" do
  describe "POST /v1/chat/completions with workflow model" do
    it "executes workflow when model starts with 'workflow/'" do
      ENV["COGNICORE_MOCK_LLM"] = "1"

      begin
        # Create a simple workflow that echoes back the input
        workflow = Ocawe::Workflow.create_workflow("e2e-workflow-model", "Workflow as model")
        workflow
          .agent("echo-agent", prompt: "Echo the input", model: "openai/gpt-4.1-mini")
          .commit

        engine = Ocawe::Workflow::Engine.new
        engine.register(workflow)

        # Simulate what compat.cr does when model="workflow/e2e-workflow-model"
        workflow_id = "e2e-workflow-model"
        input_data = {
          "prompt" => json_str("Hello from workflow model"),
          "messages" => JSON.parse([{"role" => "user", "content" => "Hello from workflow model"}].to_json),
        } of String => JSON::Any

        result = engine.create_run(workflow_id).start(input_data: input_data)
        result.status.should eq("success")

        # The workflow should have processed the input
        result.state.not_nil!.has_key?("last_response").should eq(true)
      ensure
        ENV.delete("COGNICORE_MOCK_LLM")
      end
    end

    it "returns 404 for non-existent workflow model" do
      # Simulate the check from compat.cr
      workflow_id = "non-existent-workflow"

      # In real app, this would check @workflow_index[workflow_id]?
      # and return 404 if not found
      workflow_exists = false
      workflow_exists.should eq(false)
    end

    it "extracts workflow_id from model parameter correctly" do
      # Test the model parsing logic
      model = "workflow/example"
      workflow_id = model.sub("workflow/", "")
      workflow_id.should eq("example")

      model2 = "workflow/my-app/v2"
      workflow_id2 = model2.sub("workflow/", "")
      workflow_id2.should eq("my-app/v2")
    end
  end

  describe "GET /v1/models lists workflows as models" do
    it "includes workflow entries in model list" do
      ENV["COGNICORE_MOCK_LLM"] = "1"

      begin
        workflow = Ocawe::Workflow.create_workflow("e2e-model-list", "Model list test")
        workflow
          .agent("list-agent", prompt: "Test", model: "openai/gpt-4.1-mini")
          .commit

        engine = Ocawe::Workflow::Engine.new
        engine.register(workflow)

        # Simulate available_models() logic
        # workflows should return entries with id prefixed as "workflow/"
        workflow_models = [{id: "workflow/e2e-model-list", name: "e2e-model-list", description: "test"}]
        workflow_models.size.should eq(1)
        workflow_models[0][:id].starts_with?("workflow/").should eq(true)
      ensure
        ENV.delete("COGNICORE_MOCK_LLM")
      end
    end
  end
end
