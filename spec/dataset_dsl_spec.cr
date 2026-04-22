require "./spec_helper"
require "file_utils"

describe "dataset dsl imports" do
  it "parses json and csv dataset sources with schema description" do
    tmp_dir = "/tmp/cogni_dataset_dsl_#{Random.rand(1_000_000)}"
    Dir.mkdir_p(tmp_dir)

    begin
      File.write(
        File.join(tmp_dir, "tickets.json"),
        %({"items":[{"id":"j1","text":"urgent outage"},{"id":"j2","text":"billing issue"}]})
      )
      File.write(
        File.join(tmp_dir, "scores.csv"),
        "id,name,score\nc1,Ada,10\nc2,Linus,7\n"
      )

      workflow_file = File.join(tmp_dir, "datasets.acd.cr")
      File.write(workflow_file, <<-WORKFLOW)
workflow "dataset-imports" do
  dataset "tickets" do
    description "Imported from json"
    schema_description "Ticket object with text"
    schema Schema::Types.object({"text" => Schema::Types.of(String)})
    json "tickets.json", root_key: "items"
  end

  dataset "scores" do
    schema Schema::Types.object({"name" => Schema::Types.of(String), "score" => Schema::Types.of(Int32)})
    csv "scores.csv"
  end
end
WORKFLOW

      bundle = ACD::Discovery::WorkflowBundle.new(
        id: "dataset-imports",
        root_path: tmp_dir,
        workflow_file: workflow_file,
        agents_dir: File.join(tmp_dir, "agents"),
        skills_dir: File.join(tmp_dir, "skills"),
        source_root_type: "preferred",
      )

      app = ACD::Kemal::App.new(0)
      definition = app.test_load_workflow_definition(bundle, [] of ACD::Agents::LoadedAgent)
      definition.id.should eq("dataset-imports")

      tickets = app.test_dataset_service.get_dataset("tickets")
      tickets.not_nil!.schema_description.should eq("Ticket object with text")
      tickets.not_nil!.source_format.should eq("json")
      app.test_dataset_service.list_items("tickets").size.should eq(2)
      app.test_dataset_service.list_items("scores").first.payload["score"].as_i.should eq(10)
    ensure
      FileUtils.rm_rf(tmp_dir)
    end
  end
end
