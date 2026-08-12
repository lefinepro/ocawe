require "./spec_helper"
require "../caws/15-reproducible-pipeline/plugins/functions/normalize_text"

describe "reproducible pipeline example" do
  it "loads a typed, tested local-function pipeline" do
    root = File.expand_path("../caws/15-reproducible-pipeline", __DIR__)
    bundle = ACD::Discovery::CawfileLoader.load(root, "15-reproducible-pipeline").not_nil!
    loader = bundle.crystal_loader.not_nil!

    bundle.input_type.should eq("ReproducibleTextInput")
    bundle.output_type.should eq("ReproducibleTextOutput")
    bundle.container.not_nil!.files.should eq(["plugins/functions"])
    loader.requires.should be_empty
    loader.registry_files.map { |path| Path[path].relative_to(Path[root]).to_s }.should eq([
      "plugins/functions/normalize_text.cr",
    ])

    test = bundle.tests.first
    test.name.should eq("normalizes whitespace")
    assertion = test.assertions.first
    assertion.workflow_id.should eq("15-reproducible-pipeline")
    assertion.equality.should eq("Reproducible pipeline")
  end

  it "normalizes whitespace while preserving the test tag" do
    ctx = Ocawe::Workflow::NodeContext.new(
      workflow_id: "15-reproducible-pipeline",
      run_id: "reproducible-run",
      node_id: "normalize-text",
      input_data: {
        "input" => json_str("Reproducible   pipeline   #[normalizes-whitespace-test-id]"),
      },
      state: {} of String => JSON::Any,
    )

    result = Ocawe::RegistryApi.call_function("normalize_text", ctx)
    result["text"].as_s.should eq("Reproducible pipeline #[normalizes-whitespace-test-id]")
    result["status"].as_s.should eq("ok")
  end
end
