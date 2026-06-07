require "./e2e_spec_helper"

describe "E2E: Error Handling Cases" do
  describe "guardrails" do
    it "blocks input containing blocked terms" do
      ENV["COGNICORE_MOCK_LLM"] = "1"

      begin
        workflow = Ocawe::Workflow.create_workflow("e2e-guardrails-block", "Guardrails block test")
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

        engine = Ocawe::Workflow::Engine.new
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
        input_schema = Ocawe::Workflows::DSL::CrystalDSL.compile(
          "Schema::Types.object({\"input\" => Schema::Types.object({\"task\" => Schema::Types.of(String)})}, strict: false)",
          "e2e-input-schema"
        )

        workflow = Ocawe::Workflow.create_workflow("e2e-schema-validation", "Schema validation")
        workflow
          .agent(
            "schema-agent",
            prompt: "Process the task",
            model: "openai/gpt-4.1-mini",
            input_schema: input_schema
          )
          .commit

        engine = Ocawe::Workflow::Engine.new
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
      expect_raises(Ocawe::Workflows::DSL::CrystalDSL::ParseError) do
        Ocawe::Workflows::DSL::CrystalDSL.compile(
          "Schema::Types.unknown_method()",
          "invalid-schema"
        )
      end
    end

    it "validates output schema is superset of input schema" do
      input_schema = Ocawe::Workflows::DSL::CrystalDSL.compile(
        "Schema::Types.object({\"required_field\" => Schema::Types.of(String)}, strict: true)",
        "e2e-input-superset"
      )

      # Output missing required field from input
      output_schema = Ocawe::Workflows::DSL::CrystalDSL.compile(
        "Schema::Types.object({\"other_field\" => Schema::Types.of(String)}, strict: true)",
        "e2e-output-missing"
      )

      expect_raises(Ocawe::Workflows::DSL::ValidationError, /required_field/) do
        Ocawe::Workflows::DSL::Compatibility.ensure_output_superset!(input_schema, output_schema)
      end
    end
  end

  describe "exec/node kind errors" do
    it "fails on unknown node kind reference" do
      workflow = Ocawe::Workflow.create_workflow("e2e-run-invalid", "Invalid run")
      workflow
        .step(Ocawe::NodeKind.new("missing-function"), id: "missing-function")
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      result = engine.create_run("e2e-run-invalid").start
      result.status.should eq("failed")
      result.error.not_nil!.message.includes?("unknown node kind").should eq(true)
    end

    it "handles node kind function that raises error" do
      Ocawe::Workflow.register_function("e2e_error_tool") do |_ctx|
        raise "Intentional run error"
        {} of String => JSON::Any
      end
      Ocawe::RegistryApi.node_kind("e2e_error_tool") do |ctx, _parameters|
        Ocawe::RegistryApi.call_function("e2e_error_tool", ctx)
      end

      workflow = Ocawe::Workflow.create_workflow("e2e-run-error", "Run error test")
      workflow
        .step(Ocawe::NodeKind.new("e2e_error_tool"), id: "e2e_error_tool")
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-run-error")
      result = run.start
      result.status.should eq("failed")
      result.error.not_nil!.message.includes?("Intentional run error").should eq(true)
    end
  end

  describe "workflow state errors" do
    it "rejects modifications to committed workflow" do
      workflow = Ocawe::Workflow.create_workflow("e2e-committed", "Committed workflow")
      workflow
        .step(Ocawe::Workflow::WorkflowNode.new("node", Ocawe::Workflow::NodeKind::Control) do |_ctx|
          Ocawe::Workflow::WorkflowNodeResult.continue({"done" => json_bool(true)})
        end)
        .commit

      expect_raises(Exception, /committed/) do
        workflow.step(Ocawe::Workflow::WorkflowNode.new("after-commit", Ocawe::Workflow::NodeKind::Control) do |_ctx|
          Ocawe::Workflow::WorkflowNodeResult.continue({"error" => json_bool(true)})
        end)
      end
    end
  end
end
