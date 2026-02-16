require "./e2e_spec_helper"

describe "E2E: Error Handling Cases" do
  describe "guardrails" do
    it "blocks input containing blocked terms" do
      ENV["COGNICORE_MOCK_LLM"] = "1"

      begin
        workflow = CogniCore::Workflow.create_workflow("e2e-guardrails-block", "Guardrails block test")
        workflow
          .agent(
            "guarded-agent",
            prompt: "You are a test agent.",
            model: "openai/gpt-4.1-mini",
            guardrails_config: {
              "input" => JSON.parse({
                "blocked_terms" => ["prohibited", "blocked"],
              }.to_json),
            } of String => JSON::Any
          )
          .commit

        engine = CogniCore::Workflow::Engine.new
        engine.register(workflow)

        # Test with blocked term
        blocked_result = engine.create_run("e2e-guardrails-block").start(
          input_data: {"task" => json_str("This is prohibited content")}
        )
        blocked_result.status.should eq("failed")
        blocked_result.error.not_nil!.message.includes?("guardrail violation").should eq(true)

        # Test with allowed content
        allowed_result = engine.create_run("e2e-guardrails-block").start(
          input_data: {"task" => json_str("This is allowed content")}
        )
        allowed_result.status.should eq("success")
      ensure
        ENV.delete("COGNICORE_MOCK_LLM")
      end
    end
  end

  describe "schema validation" do
    it "rejects invalid input that doesn't match schema" do
      ENV["COGNICORE_MOCK_LLM"] = "1"

      begin
        input_schema = CogniCore::Schema::CrystalDSL.compile(
          "Schema::Types.object({\"input\" => Schema::Types.object({\"task\" => Schema::Types.of(String)})}, strict: false)",
          "e2e-input-schema"
        )

        workflow = CogniCore::Workflow.create_workflow("e2e-schema-validation", "Schema validation")
        workflow
          .agent(
            "schema-agent",
            prompt: "Process the task",
            model: "openai/gpt-4.1-mini",
            input_schema: input_schema
          )
          .commit

        engine = CogniCore::Workflow::Engine.new
        engine.register(workflow)

        # Missing required field
        invalid = engine.create_run("e2e-schema-validation").start(
          input_data: {"other_field" => json_str("value")}
        )
        invalid.status.should eq("failed")
        invalid.error.not_nil!.message.includes?("task is required").should eq(true)

        # Valid input
        valid = engine.create_run("e2e-schema-validation").start(
          input_data: {"task" => json_str("Valid task")}
        )
        valid.status.should eq("success")
      ensure
        ENV.delete("COGNICORE_MOCK_LLM")
      end
    end

    it "rejects unsupported schema DSL expressions" do
      expect_raises(CogniCore::Schema::CrystalDSL::ParseError) do
        CogniCore::Schema::CrystalDSL.compile(
          "Schema::Types.unknown_method()",
          "invalid-schema"
        )
      end
    end

    it "validates output schema is superset of input schema" do
      input_schema = CogniCore::Schema::CrystalDSL.compile(
        "Schema::Types.object({\"required_field\" => Schema::Types.of(String)}, strict: true)",
        "e2e-input-superset"
      )

      # Output missing required field from input
      output_schema = CogniCore::Schema::CrystalDSL.compile(
        "Schema::Types.object({\"other_field\" => Schema::Types.of(String)}, strict: true)",
        "e2e-output-missing"
      )

      expect_raises(CogniCore::Schema::ValidationError, /required_field/) do
        CogniCore::Schema::Compatibility.ensure_output_superset!(input_schema, output_schema)
      end
    end
  end

  describe "tool errors" do
    it "rejects non-snake_case tool function names" do
      workflow = CogniCore::Workflow.create_workflow("e2e-tool-invalid", "Invalid tool")

      expect_raises(Exception, /snake_case/) do
        workflow.tool("invalid-tool-name")
      end
    end

    it "handles tool function that raises error" do
      CogniCore::Workflow.register_tool("e2e_error_tool") do |_ctx|
        raise "Intentional tool error"
        {} of String => JSON::Any
      end

      workflow = CogniCore::Workflow.create_workflow("e2e-tool-error", "Tool error test")
      workflow
        .tool("e2e_error_tool")
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-tool-error")
      result = run.start
      result.status.should eq("failed")
      result.error.not_nil!.message.includes?("Intentional tool error").should eq(true)
    end
  end

  describe "workflow state errors" do
    it "rejects modifications to committed workflow" do
      workflow = CogniCore::Workflow.create_workflow("e2e-committed", "Committed workflow")
      workflow
        .map("node") { |_ctx| {"done" => json_bool(true)} }
        .commit

      expect_raises(Exception, /committed/) do
        workflow.map("after-commit") { |_ctx| {"error" => json_bool(true)} }
      end
    end
  end
end
