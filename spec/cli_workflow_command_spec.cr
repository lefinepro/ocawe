require "./spec_helper"
require "../src/cli/app"

describe OcaweCore::CLI::Main do
  it "triggers workflow by id without action" do
    captured_url = ""
    captured_body = ""

    cli = OcaweCore::CLI::Main.new(->(url : String, body : String) {
      captured_url = url
      captured_body = body
      OcaweCore::CLI::Main::TriggerResponse.new(201, %({"ok":true}))
    })

    cli.run(["workflow", "solver"], program_name: "ocawe")

    captured_url.should eq("http://127.0.0.1:4111/v1/triggers/workflows/solver")
    JSON.parse(captured_body).as_h.empty?.should eq(true)
  end

  it "maps workflow key=value args to payload.input" do
    captured_body = ""

    cli = OcaweCore::CLI::Main.new(->(_url : String, body : String) {
      captured_body = body
      OcaweCore::CLI::Main::TriggerResponse.new(200, %({"ok":true}))
    })

    cli.run(["workflow", "solver", "task=deploy", "force=true", "fast"], program_name: "ocawe")

    payload = JSON.parse(captured_body).as_h
    input = payload["input"].as_h
    input["task"].as_s.should eq("deploy")
    input["force"].as_bool.should eq(true)
    input["args"].as_a.map(&.as_s).should eq(["fast"])
  end

  it "routes agent command to agent trigger endpoint" do
    captured_url = ""

    cli = OcaweCore::CLI::Main.new(->(url : String, body : String) {
      captured_url = url
      OcaweCore::CLI::Main::TriggerResponse.new(200, body)
    })

    cli.run(["agent", "reviewer"], program_name: "ocawe")

    captured_url.should eq("http://127.0.0.1:4111/v1/triggers/agents/reviewer")
  end

  it "routes tool command via function trigger endpoint" do
    captured_url = ""

    cli = OcaweCore::CLI::Main.new(->(url : String, body : String) {
      captured_url = url
      OcaweCore::CLI::Main::TriggerResponse.new(200, body)
    })

    cli.run(["tool", "project_healthcheck"], program_name: "ocawe")

    captured_url.should eq("http://127.0.0.1:4111/v1/triggers/functions/project_healthcheck")
  end

  it "routes support command via skill trigger endpoint" do
    captured_url = ""

    cli = OcaweCore::CLI::Main.new(->(url : String, body : String) {
      captured_url = url
      OcaweCore::CLI::Main::TriggerResponse.new(200, body)
    })

    cli.run(["support", "onboarding"], program_name: "ocawe")

    captured_url.should eq("http://127.0.0.1:4111/v1/triggers/skills/onboarding")
  end

  it "uses executable basename as workflow alias" do
    captured_url = ""

    cli = OcaweCore::CLI::Main.new(->(url : String, body : String) {
      captured_url = url
      OcaweCore::CLI::Main::TriggerResponse.new(200, body)
    })

    cli.run([] of String, program_name: "/usr/local/bin/ocawe_example_workflow")

    captured_url.should eq("http://127.0.0.1:4111/v1/triggers/workflows/ocawe_example_workflow")
  end
end
