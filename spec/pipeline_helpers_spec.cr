require "./spec_helper"

describe Ocawe::Pipeline do
  it "extracts content and attachment values from ActivityPub payloads" do
    activity = {
      "type" => json_str("Create"),
    } of String => JSON::Any
    object = {
      "content"    => json_str("weather Paris"),
      "attachment" => JSON.parse([
        {"type" => "PropertyValue", "name" => "orderId", "value" => "42"},
        {"type" => "PropertyValue", "name" => "resultInbox", "href" => "http://fmatch/inbox"},
      ].to_json),
    } of String => JSON::Any

    Ocawe::Pipeline.content_from(activity, object).should eq("weather Paris")
    Ocawe::Pipeline.first_string(activity, object, ["orderId"]).should eq("42")
    Ocawe::Pipeline.first_string(activity, object, ["resultInbox"]).should eq("http://fmatch/inbox")
  end

  it "coerces JSON scalar values" do
    Ocawe::Pipeline.string_value(json_str("x")).should eq("x")
    Ocawe::Pipeline.float_value(JSON.parse("12")).should eq(12.0)
    Ocawe::Pipeline.int_value(JSON.parse("12.7")).should eq(12)
    Ocawe::Pipeline.as_string(json_bool(true)).should eq("true")
  end

  it "derives order ids from marketplace request ids" do
    activity = JSON.parse({
      "id" => "https://planner.example/actors/planner/requests/build-feature-1",
      "object" => {
        "id" => "https://planner.example/actors/planner/requests/build-feature-1#proposal",
      },
    }.to_json).as_h

    Ocawe::Pipeline.order_id_from(activity, activity["object"].as_h).should eq("build-feature-1")
  end

  it "writes Orator-compatible order result files" do
    dir = File.join(Dir.tempdir, "ocawe-pipeline-result-#{Time.utc.to_unix_ms}")
    begin
      Dir.mkdir_p(dir)
      written = Ocawe::Pipeline.write_order_result("123", "done", "test-model", "http://example.test", results_dir: dir)
      written.should be_true

      parsed = JSON.parse(File.read(File.join(dir, "order-123.json")))
      parsed["order_id"].as_s.should eq("123")
      parsed["content"].as_s.should eq("done")
      parsed["model"].as_s.should eq("test-model")
      parsed["endpoint"].as_s.should eq("http://example.test")
      parsed["status"].as_s.should eq("completed")
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "does not write empty Orator order results as completed" do
    dir = File.join(Dir.tempdir, "ocawe-pipeline-empty-result-#{Time.utc.to_unix_ms}")
    begin
      Dir.mkdir_p(dir)
      written = Ocawe::Pipeline.write_order_result("empty", "  ", "test-model", results_dir: dir)
      written.should be_true

      parsed = JSON.parse(File.read(File.join(dir, "order-empty.json")))
      parsed["content"].as_s.should eq("Model returned an empty response.")
      parsed["status"].as_s.should eq("failed")
    ensure
      FileUtils.rm_rf(dir) if dir
    end
  end

  it "does not treat inbox acknowledgements as delivery content" do
    payload = JSON.parse({
      "chain" => [
        {
          "actor"  => "http://planner:8080/actors/planner",
          "inbox"  => "http://planner:8080/actors/planner/inbox",
          "status" => 202,
          "ok"     => true,
          "result" => {"handled" => true},
        },
      ],
      "delivery" => {
        "status" => 202,
        "ok"     => true,
        "result" => {"handled" => true},
      },
      "status" => "accepted",
    }.to_json)

    Ocawe::Pipeline.delivery_content(payload).should be_nil
  end

  it "builds pure Aptok marketplace request activities without pipeline metadata" do
    activity = JSON.parse(Ocawe::Pipeline.marketplace_request_activity(
      "https://planner.example/activities/1",
      "https://planner.example/actors/planner",
      "https://fmatch.example/actor/planner",
      "Plan task",
      "Create a plan",
      "https://fmatch/marketplace/resources/planning"
    )).as_h
    proposal = activity["object"].as_h
    intent = proposal["publishes"].as_h

    Aptok.valid_fep_0837?(proposal).should be_true
    activity["type"].as_s.should eq("Create")
    activity["@context"].as_a.compact_map(&.as_s?).should contain("https://w3id.org/fep/0837")
    proposal["type"].as_s.should eq("Proposal")
    proposal["purpose"].as_s.should eq("request")
    intent["action"].as_s.should eq("deliverService")
    intent["resourceConformsTo"].as_s.should eq("https://fmatch/marketplace/resources/planning")
    proposal.has_key?("attachment").should be_false
    proposal.has_key?("mediaType").should be_false
    intent.has_key?("receiver").should be_false
  end
end
