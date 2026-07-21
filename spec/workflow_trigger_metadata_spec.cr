require "./spec_helper"
require "file_utils"

describe "workflow trigger metadata" do
  it "survives generated Cawfile registration and is exposed as configured" do
    active_root = File.tempname("workflow_trigger_metadata")
    generated_root = File.join(active_root, "generated")
    Dir.mkdir_p(active_root)
    previous_root = ENV["OCAWE_GENERATED_WORKFLOWS_ROOT"]?

    begin
      ENV["OCAWE_GENERATED_WORKFLOWS_ROOT"] = generated_root
      Dir.cd(active_root) do
        app = ACD::Kemal::App.new(0)
        request = ACD::Discovery::GeneratedWorkflowRequest.parse({
          "id"              => "daily-summary",
          "name"            => "Daily summary",
          "prompt"          => "Summarize the conversation",
          "schedule"        => "0 9 * * *",
          "tag"             => "#summary",
          "trigger_message" => "summarize this conversation",
        }.to_json)

        app.test_create_generated_workflow(request)
        response = JSON.parse(app.test_workflow_details_response(request.id).not_nil!)
        triggers = response["triggers"]

        triggers["status"].as_s.should eq("configured")
        triggers["schedule"].as_s.should eq("0 9 * * *")
        triggers["trigger_message"].as_s.should eq("summarize this conversation")
        triggers["tags"].as_a.map(&.as_s).should eq(["summary"])
        triggers.to_json.should_not contain("active")
      end
    ensure
      if previous_root
        ENV["OCAWE_GENERATED_WORKFLOWS_ROOT"] = previous_root
      else
        ENV.delete("OCAWE_GENERATED_WORKFLOWS_ROOT")
      end
      FileUtils.rm_rf(active_root)
    end
  end
end
