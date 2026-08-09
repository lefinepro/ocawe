require "./spec_helper"
require "../src/framework/testing/cawfile_runner"

describe Ocawe::Testing::CawfileRunner do
  it "executes Cawfile test assertions against an Orator-compatible workflow endpoint" do
    assertion = ACD::Discovery::CawfileTestAssertion.new("hello", input: "ping", equality: "pong")
    test = ACD::Discovery::CawfileTest.new("answers directly", [assertion])
    bundle = ACD::Discovery::CawfileBundle.new("hello", tests: [test])
    seen_path = ""
    seen_body = ""
    transport = Ocawe::Testing::CawfileRunner::Transport.new do |path, body|
      seen_path = path
      seen_body = body
      {"output" => {"text" => "pong #[answers-directly-test-uuid]"}}.to_json
    end

    tag_generator = Ocawe::Testing::CawfileRunner::TagGenerator.new { |_name| "#[answers-directly-test-uuid]" }
    results = Ocawe::Testing::CawfileRunner.new("http://orator.test", transport, tag_generator).run(bundle)

    results.size.should eq(1)
    results.first.passed.should eq(true)
    seen_path.should eq("/v1/workflows/hello/runs")
    JSON.parse(seen_body)["input_data"]["input"].as_s.should eq("ping #[answers-directly-test-uuid]")
  end

  it "executes workflow/orator assertions through chat completions" do
    assertion = ACD::Discovery::CawfileTestAssertion.new("workflow/orator", input: "Reply exactly: Hi.", equality: "Hi.")
    seen_path = ""
    seen_body = ""
    transport = Ocawe::Testing::CawfileRunner::Transport.new do |path, body|
      seen_path = path
      seen_body = body
      {
        "choices" => [
          {"message" => {"content" => "Hi. #[orator-greeting-test-uuid]"}},
        ],
      }.to_json
    end
    tag_generator = Ocawe::Testing::CawfileRunner::TagGenerator.new { |_name| "#[orator-greeting-test-uuid]" }

    result = Ocawe::Testing::CawfileRunner.new("http://orator.test", transport, tag_generator)
      .run_assertion("orator greeting", assertion)

    result.passed.should eq(true)
    seen_path.should eq("/v1/chat/completions")
    body = JSON.parse(seen_body)
    body["model"].as_s.should eq("workflow/orator")
    body["messages"][0]["content"].as_s.should eq("Reply exactly: Hi. #[orator-greeting-test-uuid]")
  end

  it "reports equality failures with actual output" do
    assertion = ACD::Discovery::CawfileTestAssertion.new("hello", input: "ping", equality: "pong")
    transport = Ocawe::Testing::CawfileRunner::Transport.new do |_path, _body|
      {"output" => {"content" => "wrong #[answers-directly-test-uuid]"}}.to_json
    end
    tag_generator = Ocawe::Testing::CawfileRunner::TagGenerator.new { |_name| "#[answers-directly-test-uuid]" }

    result = Ocawe::Testing::CawfileRunner.new("http://orator.test", transport, tag_generator)
      .run_assertion("answers directly", assertion)

    result.passed.should eq(false)
    result.expected.should eq("pong")
    result.actual.should eq("wrong #[answers-directly-test-uuid]")
  end

  it "fails when the generated test tag is missing from output even if equality matches" do
    assertion = ACD::Discovery::CawfileTestAssertion.new("hello", input: "ping", equality: "pong")
    transport = Ocawe::Testing::CawfileRunner::Transport.new do |_path, _body|
      {"output" => {"text" => "pong"}}.to_json
    end
    tag_generator = Ocawe::Testing::CawfileRunner::TagGenerator.new { |_name| "#[tag-passthrough-test-uuid]" }

    result = Ocawe::Testing::CawfileRunner.new("http://orator.test", transport, tag_generator)
      .run_assertion("tag passthrough", assertion)

    result.passed.should eq(false)
    result.missing_tags.should eq(["#[tag-passthrough-test-uuid]"])
  end

  it "waits for an async workflow run result" do
    assertion = ACD::Discovery::CawfileTestAssertion.new("hello", input: "ping", equality: "pong", wait_seconds: 2)
    calls = [] of String
    transport = Ocawe::Testing::CawfileRunner::Transport.new do |path, _body|
      calls << path
      if path == "/v1/workflows/hello/runs"
        {"status" => "queued", "run_id" => "run-1"}.to_json
      else
        {"output" => {"text" => "pong #[wait-test-uuid]"}}.to_json
      end
    end
    tag_generator = Ocawe::Testing::CawfileRunner::TagGenerator.new { |_name| "#[wait-test-uuid]" }

    result = Ocawe::Testing::CawfileRunner.new("http://orator.test", transport, tag_generator)
      .run_assertion("wait", assertion)

    result.passed.should eq(true)
    calls.should eq(["/v1/workflows/hello/runs", "/v1/workflows/hello/runs/run-1"])
  end
end
