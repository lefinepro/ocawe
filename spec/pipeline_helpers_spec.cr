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

  it "builds internal model context from OpenAI chat history without public service labels" do
    messages = JSON.parse([
      {"role" => "system", "content" => "Use short answers."},
      {"role" => "user", "content" => "My project is called Atlas."},
      {"role" => "assistant", "content" => "Noted."},
      {"role" => "user", "content" => [{"type" => "text", "text" => "What is my project called?"}]},
    ].to_json).as_a

    prompt = Ocawe::Pipeline.chat_context_prompt(messages, "What is my project called?")

    prompt.should contain("Internal conversation context for answering only.")
    prompt.should contain("System: Use short answers.")
    prompt.should contain("User: My project is called Atlas.")
    prompt.should contain("Assistant: Noted.")
    prompt.should contain("Current user request. Answer this request directly:")
    prompt.should contain("What is my project called?")
    prompt.should_not contain("Conversation Context")
    prompt.should_not contain("Conversation context:")
  end

  it "supports custom context intro and current-request label" do
    messages = JSON.parse([
      {"role" => "user", "content" => "Earlier request."},
      {"role" => "user", "content" => "Current request."},
    ].to_json).as_a

    prompt = Ocawe::Pipeline.chat_context_prompt(
      messages,
      "Current request.",
      "Private history follows.",
      "Answer this exact request:",
    )

    prompt.should contain("Private history follows.")
    prompt.should contain("Answer this exact request:")
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
end
