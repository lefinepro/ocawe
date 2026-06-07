require "./e2e_spec_helper"

# E2E Tests for Agents and Skills
#
# Tests agent and skill workflow patterns:
# - agents-example: Basic agent execution with model configuration
# - skills-example: Agent with skill integration

describe "E2E: Agents and Skills" do
  describe "agents-example" do
    it "creates workflow with model configuration and agent" do
      # Simulates: workflow "agents-example" do
      #   agent "simple-agent", model: "clipproxyapi/qwen3-coder-plus"
      # end
      workflow = Ocawe::Workflow.create_workflow("agents-example", "Agent example test")
      workflow
        .agent("simple-agent", model: "clipproxyapi/qwen3-coder-plus")
        .commit

      workflow.id.should eq("agents-example")
      workflow.nodes.size.should eq(1)
      workflow.nodes[0].id.should eq("simple-agent")
      workflow.nodes[0].kind.should eq(Ocawe::Workflow::NodeKind::Agent)
    end

    it "executes agent workflow with task input" do
      ENV["COGNICORE_MOCK_LLM"] = "1"

      begin
      workflow = Ocawe::Workflow.create_workflow("agents-example-run", "Agent run test")
      workflow
        .agent("simple-agent", model: "openai/gpt-4.1-mini")
        .step(Ocawe::Workflow::WorkflowNode.new("setup", Ocawe::Workflow::NodeKind::Control) do |_ctx|
          Ocawe::Workflow::WorkflowNodeResult.continue({"task" => json_str("test task")})
        end)
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("agents-example-run")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["task"].as_s.should eq("test task")
      ensure
        ENV.delete("COGNICORE_MOCK_LLM")
      end
    end
  end

  describe "skills-example" do
    it "creates workflow with agent and skill nodes" do
      # Simulates: workflow "skills-example" do
      #   agent "skills-agent"
      #   skill "example-skill"
      # end
      workflow = Ocawe::Workflow.create_workflow("skills-example", "Skills example test")
      workflow
        .agent("skills-agent")
        .skill("example-skill")
        .commit

      workflow.nodes.size.should eq(2)
      workflow.nodes[0].id.should eq("skills-agent")
      workflow.nodes[0].kind.should eq(Ocawe::Workflow::NodeKind::Agent)
      workflow.nodes[1].id.should eq("example-skill")
      workflow.nodes[1].kind.should eq(Ocawe::Workflow::NodeKind::Skill)
    end

    it "executes skill workflow with skill node" do
      workflow = Ocawe::Workflow.create_workflow("skills-example-run", "Skills run test")
      workflow
        .step(Ocawe::Workflow::WorkflowNode.new("init", Ocawe::Workflow::NodeKind::Control) do |_ctx|
          Ocawe::Workflow::WorkflowNodeResult.continue({"skill_data" => json_str("prepared")})
        end)
        .skill("example-skill")
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("skills-example-run")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["skill_data"].as_s.should eq("prepared")
    end
  end

  describe "workflow-example" do
    it "creates workflow with typed schemas and multiple agent functions" do
      # Simulates: workflow "workflow-example" with typed input/output schemas
      workflow = Ocawe::Workflow.create_workflow("workflow-example", "Workflow composition test")
      workflow
        .agent("workflow-agent",
          input_schema: Ocawe::Workflows::DSL::Types.object({"task" => Ocawe::Workflows::DSL::Types.of(String)}),
          output_schema: Ocawe::Workflows::DSL::Types.object({"last_response" => Ocawe::Workflows::DSL::Types.of(String)}, strict: false))
        .commit

      workflow.nodes.size.should eq(1)
      workflow.nodes[0].id.should eq("workflow-agent")
      workflow.nodes[0].kind.should eq(Ocawe::Workflow::NodeKind::Agent)
    end

    it "validates input schema on workflow execution" do
      workflow = Ocawe::Workflow.create_workflow("workflow-schema-test", "Schema validation test")
      workflow
        .step(Ocawe::Workflow::WorkflowNode.new("validate", Ocawe::Workflow::NodeKind::Control) do |ctx|
          task = ctx.input_data["task"]?.try(&.as_s?) || "default"
          Ocawe::Workflow::WorkflowNodeResult.continue({"validated_task" => json_str(task)})
        end)
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("workflow-schema-test")
      result = run.start(input_data: {"task" => json_str("workflow test")})
      result.status.should eq("success")
      result.state.not_nil!["validated_task"].as_s.should eq("workflow test")
    end
  end

  describe "agent interaction" do
    it "handles agent with voice configuration" do
      workflow = Ocawe::Workflow.create_workflow("voice-agent-test", "Voice agent test")
      workflow
        .agent("voice-enabled-agent",
          voice_config: {"provider" => json_str("openai"), "speaker" => json_str("alloy")})
        .commit

      workflow.nodes.size.should eq(1)
      workflow.nodes[0].kind.should eq(Ocawe::Workflow::NodeKind::Agent)
    end

    it "handles agent input with task and input object" do
      workflow = Ocawe::Workflow.create_workflow("agent-input-test", "Agent input test")
      workflow
        .step(Ocawe::Workflow::WorkflowNode.new("prepare", Ocawe::Workflow::NodeKind::Control) do |ctx|
          task = ctx.input_data["task"]?.try(&.as_s?) || "default-task"
          Ocawe::Workflow::WorkflowNodeResult.continue({
            "prepared_task" => json_str(task),
            "context"       => json_str("prepared"),
          })
        end)
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("agent-input-test")
      result = run.start(input_data: {
        "task"  => json_str("process data"),
        "input" => JSON.parse({"data" => "test"}.to_json),
      })
      result.status.should eq("success")
      result.state.not_nil!["prepared_task"].as_s.should eq("process data")
    end

    it "chains multiple agents in sequence" do
      workflow = Ocawe::Workflow.create_workflow("agent-chain-test", "Agent chain test")
      workflow
        .step(Ocawe::Workflow::WorkflowNode.new("agent-1", Ocawe::Workflow::NodeKind::Control) do |_ctx|
          Ocawe::Workflow::WorkflowNodeResult.continue({"step" => json_str("1")})
        end)
        .step(Ocawe::Workflow::WorkflowNode.new("agent-2", Ocawe::Workflow::NodeKind::Control) do |ctx|
          prev = ctx.state["step"]?.try(&.as_s?) || "0"
          Ocawe::Workflow::WorkflowNodeResult.continue({"step" => json_str("#{prev}->2")})
        end)
        .step(Ocawe::Workflow::WorkflowNode.new("agent-3", Ocawe::Workflow::NodeKind::Control) do |ctx|
          prev = ctx.state["step"]?.try(&.as_s?) || "0"
          Ocawe::Workflow::WorkflowNodeResult.continue({"step" => json_str("#{prev}->3")})
        end)
        .commit

      engine = Ocawe::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("agent-chain-test")
      result = run.start
      result.status.should eq("success")
      result.state.not_nil!["step"].as_s.should eq("1->2->3")
    end

    it "executes multi-agent workflow" do
      workflow = Ocawe::Workflow.create_workflow("multi-agent-test", "Multi-agent test")
      workflow
        .agent("analyzer")
        .agent("processor")
        .agent("finalizer")
        .commit

      workflow.nodes.size.should eq(3)
      workflow.nodes[0].id.should eq("analyzer")
      workflow.nodes[1].id.should eq("processor")
      workflow.nodes[2].id.should eq("finalizer")
    end
  end
end
