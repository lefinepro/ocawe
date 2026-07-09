require "file_utils"
require "./spec_helper"

describe "OpenAI chat completion retrieve compatibility" do
  around_each do |example|
    previous = ENV["ORATOR_RESULTS_DIR"]?
    dir = File.join(Dir.tempdir, "ocawe-chat-retrieve-#{Random::Secure.hex(6)}")
    ENV["ORATOR_RESULTS_DIR"] = dir
    FileUtils.mkdir_p(File.join(dir, "tasks"))

    begin
      example.run
    ensure
      if previous
        ENV["ORATOR_RESULTS_DIR"] = previous
      else
        ENV.delete("ORATOR_RESULTS_DIR")
      end
      FileUtils.rm_rf(dir)
    end
  end

  it "normalizes OpenAI and legacy task ids" do
    app = ACD::Kemal::App.new(0)

    app.test_chat_completion_task_ref("chatcmpl_orator_project_name-id").should eq("project_name-id")
    app.test_chat_completion_task_ref("#[project_name-id]").should eq("")
    app.test_chat_completion_task_ref("chatcmpl_other_project_name-id").should eq("")
    app.test_chat_completion_task_ref("project_name-id").should eq("")
    app.test_chat_completion_task_ref("../project_name-id").should eq("")
  end

  it "returns a pending chat completion when the task has no result yet" do
    app = ACD::Kemal::App.new(0)
    write_task("project_name-id", status: "queued")

    completion = JSON.parse(app.test_retrieve_chat_completion("chatcmpl_orator_project_name-id").not_nil!.to_json)

    completion["id"].as_s.should eq("chatcmpl_orator_project_name-id")
    completion["object"].as_s.should eq("chat.completion")
    completion["choices"][0]["message"]["content"].as_s.should eq("The task is still running.")
  end

  it "returns a completed result and persists task state from the order result" do
    app = ACD::Kemal::App.new(0)
    write_task("project_name-id", status: "queued", order_id: "42")
    File.write(File.join(results_dir, "order-42.json"), {"status" => "completed", "content" => "final answer"}.to_json)

    completion = JSON.parse(app.test_retrieve_chat_completion("chatcmpl_orator_project_name-id").not_nil!.to_json)

    completion["choices"][0]["message"]["content"].as_s.should eq("final answer")
    task = JSON.parse(File.read(File.join(results_dir, "tasks", "project_name-id.json")))
    task["status"].as_s.should eq("completed")
    task["result"].as_s.should eq("final answer")
  end

  it "returns nil for unknown completion ids" do
    app = ACD::Kemal::App.new(0)

    app.test_retrieve_chat_completion("chatcmpl_orator_missing").should be_nil
  end
end

private def results_dir : String
  ENV["ORATOR_RESULTS_DIR"].to_s
end

private def write_task(ref : String, status : String, order_id : String = "")
  task = {
    "ref"           => ref,
    "completion_id" => "chatcmpl_orator_#{ref}",
    "model"         => "workflow/orator",
    "order_id"      => order_id,
    "status"        => status,
    "summary"       => "test task",
    "created_at"    => "2026-07-03T00:00:00Z",
    "updated_at"    => "2026-07-03T00:00:00Z",
  }
  File.write(File.join(results_dir, "tasks", "#{ref}.json"), task.to_json)
end
