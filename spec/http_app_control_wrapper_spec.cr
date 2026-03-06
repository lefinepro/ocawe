require "./spec_helper"
require "file_utils"

describe "ACD::Kemal::App control wrapper" do
  it "halts wrapped if-branch execution on first non-continue result" do
    app = ACD::Kemal::App.new(0)
    executed = false

    first = Cogni::Workflow::WorkflowNode.new("first", Cogni::Workflow::NodeKind::Control) do |_ctx|
      Cogni::Workflow::WorkflowNodeResult.suspend(
        {"reason" => json_str("pause")},
        resume_label: "first-stop"
      )
    end

    second = Cogni::Workflow::WorkflowNode.new("second", Cogni::Workflow::NodeKind::Control) do |_ctx|
      executed = true
      Cogni::Workflow::WorkflowNodeResult.continue({"should_not_run" => json_bool(true)})
    end

    wrapped = app.test_wrap_nodes_in_control([first, second], "if-branch")
    ctx = Cogni::Workflow::NodeContext.new(
      workflow_id: "wf",
      run_id: "run",
      node_id: "if-branch",
      input_data: {} of String => JSON::Any,
      state: {} of String => JSON::Any
    )

    result = wrapped.execute(ctx)
    result.action.should eq(Cogni::Workflow::NodeAction::Suspend.to_s.downcase)
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
  exec "tool_extract_source_archive_content", runtime: {shell: "bash"}
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

      app = ACD::Kemal::App.new(0)
      definition = app.test_load_workflow_definition(bundle, [] of ACD::Agents::LoadedAgent)
      definition.id.should eq("types_before_workflow")
      definition.nodes.size.should eq(1)
      definition.nodes.first.kind.should eq(Cogni::Workflow::NodeKind::Exec)
    ensure
      FileUtils.rm_rf(tmp_dir)
    end
  end
end
