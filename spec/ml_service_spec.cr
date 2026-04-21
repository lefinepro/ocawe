require "./spec_helper"

describe Cogni::ML::Service do
  it "registers models from dsl and records artifacts" do
    service = Cogni::ML::Service.new
    service.register_from_dsl(
      "ticket-classifier",
      source_file: "/tmp/ml_pipeline.acd.cr",
      description: "Ticket triage",
      task: "classification",
      runtime: {
        "adapter" => json_str("cogni_ml"),
        "backends" => json_any(["cuda", "amd"]),
      },
      metadata: {
        "learning_rate" => json_any(0.001),
      }
    )

    model = service.require_model!("ticket-classifier")
    model.task.should eq("classification")
    model.backends.should eq(["cuda", "amd"])
    model.metadata.not_nil!["learning_rate"].raw.should eq(0.001)

    artifact = service.record_artifact(
      "ticket-classifier",
      "checkpoint",
      metadata: {"epoch" => json_any(2)}
    )
    artifact.model_id.should eq("ticket-classifier")
    service.list_artifacts("ticket-classifier").size.should eq(1)
  end
end
