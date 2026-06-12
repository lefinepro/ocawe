require "./e2e_spec_helper"

describe "E2E: ACP Protocol Support" do
  describe "exec with runtime: acp" do
    it "executes ACP agent via exec directive" do
      mock_script = File.join(__DIR__, "..", "support", "mock_acp_agent.cr")
      unless File.file?(mock_script)
        skip "mock_acp_agent.cr not found"
      end

      workflow = Ocawe::Workflow.create_workflow("e2e-acp-exec", "ACP agent via exec")
      workflow
        .exec(
          "mock-acp",
          runtime: {
            "acp" => json_h({
              "command" => "ruby",
              "args" => [mock_script],
            })
          }
        )
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      result = engine.create_run("e2e-acp-exec").start(input_data: {
        "task" => json_str("Test ACP protocol"),
      })

      result.status.should eq("success")
      result.output.should_not be_nil
      output = result.output.not_nil!
      output["session_id"]?.should_not be_nil
      output["stop_reason"]?.try(&.as_s?).should eq("end_turn")
      output["content"]?.should_not be_nil
    end

    it "passes input to ACP agent" do
      mock_script = File.join(__DIR__, "..", "support", "mock_acp_agent.cr")
      unless File.file?(mock_script)
        skip "mock_acp_agent.cr not found"
      end

      workflow = Ocawe::Workflow.create_workflow("e2e-acp-input", "ACP agent input test")
      workflow
        .exec(
          "codex",
          runtime: {
            "acp" => json_h({
              "command" => "ruby",
              "args" => [mock_script],
            })
          }
        )
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      result = engine.create_run("e2e-acp-input").start(input_data: {
        "input" => json_str("Write a function to calculate fibonacci"),
      })

      result.status.should eq("success")
      output = result.output.not_nil!
      content = output["content"]?.try(&.as_s?) || ""
      content.should include("Mock ACP agent received")
    end
  end

  describe "ACP with environment variables" do
    it "passes environment variables to ACP agent" do
      mock_script = File.join(__DIR__, "..", "support", "mock_acp_agent.cr")
      unless File.file?(mock_script)
        skip "mock_acp_agent.cr not found"
      end

      workflow = Ocawe::Workflow.create_workflow("e2e-acp-env", "ACP with env")
      workflow
        .exec(
          "codex",
          runtime: {
            "acp" => json_h({
              "command" => "ruby",
              "args" => [mock_script],
              "env" => json_h({
                "API_KEY" => "test_key_123"
              })
            })
          },
          env: {
            "EXTRA_VAR" => json_str("extra_value")
          }
        )
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      result = engine.create_run("e2e-acp-env").start(input_data: {
        "task" => json_str("Test with env vars"),
      })

      result.status.should eq("success")
    end
  end
end

# Helper method for creating JSON::Any hash
private def json_h(hash : Hash(String, String | Hash(String, String)))
  JSON.parse(hash.to_json)
end
