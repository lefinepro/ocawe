require "./spec_helper"
require "file_utils"

class ACD::HTTP::App
  def test_load_workflow_definition(
    bundle : ACD::Discovery::WorkflowBundle,
    loaded_agents : Array(ACD::Agents::LoadedAgent)
  ) : Cogni::Workflows::Declarative::WorkflowDefinition
    load_workflow_definition(bundle, loaded_agents)
  end

  def test_wrap_nodes_in_control(
    nodes : Array(Cogni::Workflows::Declarative::WorkflowNode),
    name : String
  ) : Cogni::Workflows::Declarative::WorkflowNode
    wrap_nodes_in_control(nodes, name)
  end
end

describe "ACD::HTTP::App control wrapper" do
  it "halts wrapped if-branch execution on first non-continue result" do
    app = ACD::HTTP::App.new(0)
    executed = false

    first = Cogni::Workflows::Declarative::WorkflowNode.new("first", Cogni::Workflows::Declarative::NodeKind::Control) do |_ctx|
      Cogni::Workflows::Declarative::WorkflowNodeResult.suspend(
        {"reason" => json_str("pause")},
        resume_label: "first-stop"
      )
    end

    second = Cogni::Workflows::Declarative::WorkflowNode.new("second", Cogni::Workflows::Declarative::NodeKind::Control) do |_ctx|
      executed = true
      Cogni::Workflows::Declarative::WorkflowNodeResult.continue({"should_not_run" => json_bool(true)})
    end

    wrapped = app.test_wrap_nodes_in_control([first, second], "if-branch")
    ctx = Cogni::Workflows::Declarative::NodeContext.new(
      workflow_id: "wf",
      run_id: "run",
      node_id: "if-branch",
      input_data: {} of String => JSON::Any,
      state: {} of String => JSON::Any
    )

    result = wrapped.execute(ctx)
    result.action.should eq(Cogni::Workflows::Declarative::NodeAction::Suspend.to_s.downcase)
    result.resume_labels.should eq(["first-stop"])
    executed.should eq(false)
  end

  it "parses workflow files that include Crystal type declarations before workflow block" do
    tmp_dir = "/tmp/cogni_http_app_spec_#{Random.rand(1_000_000)}"
    Dir.mkdir_p(tmp_dir)
    begin
      workflow_file = File.join(tmp_dir, "types_before_workflow.acd.cr")
      File.write(workflow_file, <<-WORKFLOW)
struct ExampleInput
  include JSON::Serializable
  getter task : String
end

workflow "types_before_workflow" do
  run "tool_extract_source_archive_content"
end
WORKFLOW

      bundle = ACD::Discovery::WorkflowBundle.new(
        id: "types_before_workflow",
        root_path: tmp_dir,
        workflow_file: workflow_file,
        agents_dir: File.join(tmp_dir, "agents"),
        skills_dir: File.join(tmp_dir, "skills"),
        source_root_type: "preferred",
      )

      app = ACD::HTTP::App.new(0)
      definition = app.test_load_workflow_definition(bundle, [] of ACD::Agents::LoadedAgent)
      definition.id.should eq("types_before_workflow")
      definition.nodes.size.should eq(1)
      definition.nodes.first.kind.should eq(Cogni::Workflows::Declarative::NodeKind::Run)
    ensure
      FileUtils.rm_rf(tmp_dir)
    end
  end
end
