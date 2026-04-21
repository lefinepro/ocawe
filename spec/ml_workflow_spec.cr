require "./spec_helper"
require "file_utils"

describe "ML workflow DSL" do
  it "registers models and executes train/embed/infer/eval nodes" do
    tmp_dir = "/tmp/cogni_ml_workflow_#{Random.rand(1_000_000)}"
    Dir.mkdir_p(tmp_dir)

    begin
      workflow_file = File.join(tmp_dir, "ml_pipeline.acd.cr")
      File.write(workflow_file, <<-WORKFLOW)
workflow "ml_pipeline" do
  dataset "tickets" do
    item({"id": "1", "text": "urgent outage"})
    item({"id": "2", "text": "billing issue"})
  end

  model "ticket-embedder", task: "embedding", runtime: {"adapter": "cogni_ml", "backends": ["cuda", "amd"]}
  model "ticket-classifier", task: "classification", runtime: {"adapter": "cogni_ml"}

  train "fit-classifier", model: "ticket-classifier", dataset: "tickets", epochs: 2
  embed "index-tickets", model: "ticket-embedder", dataset: "tickets", field: "text", persist: true, dimensions: 4
  infer "score-ticket", model: "ticket-classifier", labels: ["urgent", "normal"]
  eval "check-ticket", model: "ticket-classifier", expected: ["urgent"]
end
WORKFLOW

      bundle = ACD::Discovery::WorkflowBundle.new(
        id: "ml_pipeline",
        root_path: tmp_dir,
        workflow_file: workflow_file,
        agents_dir: File.join(tmp_dir, "agents"),
        skills_dir: File.join(tmp_dir, "skills"),
        source_root_type: "preferred",
      )

      app = ACD::Kemal::App.new(0)
      definition = app.test_load_workflow_definition(bundle, [] of ACD::Agents::LoadedAgent)
      definition.nodes.map(&.id).should eq(["fit-classifier", "index-tickets", "score-ticket", "check-ticket"])

      models = Cogni::ML.service.list_models.map(&.id)
      models.includes?("ticket-embedder").should eq(true)
      models.includes?("ticket-classifier").should eq(true)

      engine = Cogni::Workflow::Engine.new
      engine.register(definition)
      result = engine.create_run("ml_pipeline").start(input_data: {"text" => json_str("urgent outage"), "expected" => json_any(["urgent"])})

      result.status.should eq("success")
      state = result.state.not_nil!
      state["samples_seen"].as_i.should eq(2)
      state["embedding_count"].as_i.should eq(2)
      state["prediction_count"].as_i.should eq(1)
      state["accuracy"].as_f.should be >= 0.0
    ensure
      FileUtils.rm_rf(tmp_dir)
    end
  end
end
