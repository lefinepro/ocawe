require "./spec_helper"
require "file_utils"
require "http/server"

private def generated_workflow_auth_context(authorization : String? = nil)
  headers = HTTP::Headers.new
  headers["Authorization"] = authorization if authorization
  request = HTTP::Request.new("DELETE", "/v1/workflows/generated/test", headers)
  response = HTTP::Server::Response.new(IO::Memory.new)
  HTTP::Server::Context.new(request, response)
end

describe ACD::Discovery::GeneratedWorkflowRequest do
  it "strictly validates fields and safe workflow ids" do
    request = ACD::Discovery::GeneratedWorkflowRequest.parse({
      "id"              => "daily-summary",
      "name"            => "Daily summary",
      "prompt"          => "Summarize the conversation",
      "schedule"        => "0 9 * * *",
      "tag"             => "#summary",
      "trigger_message" => "create a daily summary",
    }.to_json)

    request.id.should eq("daily-summary")
    request.schedule.should eq("0 9 * * *")
    request.tag.should eq("#summary")

    expect_raises(ACD::Discovery::GeneratedWorkflowValidationError, /id must match/) do
      ACD::Discovery::GeneratedWorkflowRequest.parse({
        "id" => "../../escape", "name" => "Escape", "prompt" => "No",
      }.to_json)
    end
    expect_raises(ACD::Discovery::GeneratedWorkflowValidationError, /unknown request fields/) do
      ACD::Discovery::GeneratedWorkflowRequest.parse({
        "name" => "Unknown", "prompt" => "No", "nodes" => [] of String,
      }.to_json)
    end
  end
end

describe ACD::Discovery::GeneratedWorkflowWriter do
  it "atomically writes a loadable Cawfile with metadata and a real agent node" do
    root = File.tempname("generated_workflows")
    Dir.mkdir_p(root)
    begin
      request = ACD::Discovery::GeneratedWorkflowRequest.parse({
        "id"              => "support-flow",
        "name"            => "Support flow",
        "description"     => "Handle support requests",
        "prompt"          => "Answer clearly\nDo not emit: \"unsafe\"",
        "schedule"        => "0 8 * * 1-5",
        "tag"             => "#support",
        "trigger_message" => "help me",
        "model"           => "openai/gpt-4.1-mini",
        "conversation_id" => "conversation-1",
        "user_id"         => "user-1",
        "environment_id"  => "environment-1",
      }.to_json)

      writer = ACD::Discovery::GeneratedWorkflowWriter.new(root)
      artifact = writer.create(request)
      artifact.relative_path.should eq(File.join("support-flow", "Cawfile"))
      artifact.content.should contain("#+ocawe-trigger-message: help me")
      artifact.content.should contain("#+tags: support")
      artifact.content.should contain("@[Validate(")
      artifact.content.should contain(%q(agent "assistant", prompt: "Answer clearly\nDo not emit: \"unsafe\""))
      Dir.children(artifact.workflow_dir).should eq(["Cawfile"])

      bundle = ACD::Discovery::CawfileLoader.load(artifact.workflow_dir, request.id).not_nil!
      bundle.id.should eq(request.id)
      bundle.resources.first.tags.should eq(["support"])

      expect_raises(ACD::Discovery::GeneratedWorkflowConflictError) do
        writer.create(request)
      end
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "deletes only marked generated Cawfiles and supports rollback" do
    root = File.tempname("generated_workflow_delete")
    outside_root = File.tempname("generated_workflow_outside")
    Dir.mkdir_p(root)
    Dir.mkdir_p(outside_root)
    begin
      request = ACD::Discovery::GeneratedWorkflowRequest.parse({
        "id" => "delete-safe", "name" => "Delete safe", "prompt" => "Respond once",
      }.to_json)
      writer = ACD::Discovery::GeneratedWorkflowWriter.new(root)
      created = writer.create(request)
      note_path = File.join(created.workflow_dir, "keep.txt")
      File.write(note_path, "keep")

      staged = writer.stage_delete(request.id)
      File.exists?(File.join(created.workflow_dir, "Cawfile")).should be_false
      File.exists?(note_path).should be_true
      writer.rollback_delete(staged)
      File.read(File.join(created.workflow_dir, "Cawfile")).should eq(created.content)

      staged = writer.stage_delete(request.id)
      writer.commit_delete(staged)
      File.exists?(File.join(created.workflow_dir, "Cawfile")).should be_false
      File.read(note_path).should eq("keep")

      unmarked_dir = File.join(root, "manual-flow")
      Dir.mkdir(unmarked_dir)
      unmarked_path = File.join(unmarked_dir, "Cawfile")
      File.write(unmarked_path, %(workflow "manual-flow" do\nend\n))
      expect_raises(ACD::Discovery::GeneratedWorkflowProtectionError, /not managed/) do
        writer.stage_delete("manual-flow")
      end
      File.exists?(unmarked_path).should be_true

      outside_cawfile = File.join(outside_root, "Cawfile")
      File.write(outside_cawfile, "#{ACD::Discovery::GeneratedWorkflowWriter::GENERATED_MARKER}\n")
      File.symlink(outside_root, File.join(root, "linked-flow"))
      expect_raises(ACD::Discovery::GeneratedWorkflowProtectionError, /must not be a symlink/) do
        writer.stage_delete("linked-flow")
      end
      File.exists?(outside_cawfile).should be_true

      expect_raises(ACD::Discovery::GeneratedWorkflowValidationError, /id must match/) do
        writer.stage_delete("../../escape")
      end
    ensure
      FileUtils.rm_rf(root)
      FileUtils.rm_rf(outside_root)
    end
  end

  it "registers the generated workflow in an existing app without restart" do
    active_root = File.tempname("active_workflows")
    generated_root = File.join(active_root, "generated")
    Dir.mkdir_p(active_root)
    previous_root = ENV["OCAWE_GENERATED_WORKFLOWS_ROOT"]?

    begin
      ENV["OCAWE_GENERATED_WORKFLOWS_ROOT"] = generated_root
      Dir.cd(active_root) do
        app = ACD::Kemal::App.new(0)
        request = ACD::Discovery::GeneratedWorkflowRequest.parse({
          "id" => "hot-flow", "name" => "Hot flow", "prompt" => "Respond once",
          "environment_id" => "environment-1",
        }.to_json)

        artifact = app.test_create_generated_workflow(request)
        app.test_workflow_loaded?(request.id).should be_true
        artifact.content.should contain(%q(workflow "hot-flow" do))

        response = JSON.parse(app.test_generated_workflow_response(request, artifact))
        response["status"].as_s.should eq("created")
        response["cawfile_path"].as_s.should eq(File.join("hot-flow", "Cawfile"))
        response["environment_id"].as_s.should eq("environment-1")
        response["nodes"][0]["id"].as_s.should eq("assistant")
        response["nodes"][0]["config"]["prompt"].as_s.should eq("Respond once")
        response["nodes"].as_a.size.should eq(2)
        response["nodes"][1]["id"].as_s.should eq("output")
        response["nodes"][1]["implicit"].as_bool.should be_true
        response["edges"].as_a.size.should eq(1)
        response["edges"][0]["id"].as_s.should eq("assistant-output")
        response["edges"][0]["type"].as_s.should eq("smoothstep")
        response["edges"][0]["animated"].as_bool.should be_true
        response.to_json.should_not contain(active_root)

        locator = ACD::Discovery::WorkflowLocator.new(active_root, generated_root: generated_root)
        locator.resolve(request.id).source_root_type.should eq("generated")
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

  it "unregisters and removes a generated workflow without touching other files" do
    active_root = File.tempname("delete_active_workflow")
    generated_root = File.join(active_root, "generated")
    Dir.mkdir_p(active_root)
    previous_root = ENV["OCAWE_GENERATED_WORKFLOWS_ROOT"]?

    begin
      ENV["OCAWE_GENERATED_WORKFLOWS_ROOT"] = generated_root
      Dir.cd(active_root) do
        app = ACD::Kemal::App.new(0)
        request = ACD::Discovery::GeneratedWorkflowRequest.parse({
          "id" => "remove-hot-flow", "name" => "Remove hot flow", "prompt" => "Respond once",
        }.to_json)
        created = app.test_create_generated_workflow(request)
        app.test_workflow_loaded?(request.id).should be_true

        deleted = app.test_delete_generated_workflow(request.id)
        deleted.relative_path.should eq(File.join(request.id, "Cawfile"))
        app.test_workflow_loaded?(request.id).should be_false
        File.exists?(File.join(created.workflow_dir, "Cawfile")).should be_false
        Dir.exists?(created.workflow_dir).should be_false
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

  it "restores the generated Cawfile when unregister reload fails" do
    active_root = File.tempname("delete_rollback_workflow")
    generated_root = File.join(active_root, "generated")
    Dir.mkdir_p(active_root)
    previous_root = ENV["OCAWE_GENERATED_WORKFLOWS_ROOT"]?

    begin
      ENV["OCAWE_GENERATED_WORKFLOWS_ROOT"] = generated_root
      Dir.cd(active_root) do
        app = ACD::Kemal::App.new(0)
        request = ACD::Discovery::GeneratedWorkflowRequest.parse({
          "id" => "restore-hot-flow", "name" => "Restore hot flow", "prompt" => "Respond once",
        }.to_json)
        created = app.test_create_generated_workflow(request)

        blocker_dir = File.join(active_root, "blocker")
        Dir.mkdir(blocker_dir)
        File.write(File.join(blocker_dir, "Cawfile"), <<-CAWFILE)
          struct BlockerInput
            include JSON::Serializable
            getter input : JSON::Any?
          end

          struct BlockerOutput
            include JSON::Serializable
            getter output : JSON::Any?
          end

          @[Validate(BlockerInput, BlockerOutput)]
          workflow "blocker" do
            exec "local-script"
          end
          CAWFILE

        expect_raises(Exception, /requires runtime for non-mcp refs/) do
          app.test_delete_generated_workflow(request.id)
        end
        File.read(File.join(created.workflow_dir, "Cawfile")).should eq(created.content)
        Dir.children(created.workflow_dir).should eq(["Cawfile"])
        app.test_workflow_loaded?(request.id).should be_true
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

describe "generated workflow API authentication" do
  it "fails closed and accepts only the configured bearer token" do
    previous_key = ENV["OCAWE_API_KEY"]?
    begin
      app = ACD::Kemal::App.new(0)
      ENV["OCAWE_API_KEY"] = "delete-secret"

      valid = generated_workflow_auth_context("Bearer delete-secret")
      app.test_generated_workflow_auth_error(valid).should be_nil

      invalid = generated_workflow_auth_context("Bearer wrong-secret")
      JSON.parse(app.test_generated_workflow_auth_error(invalid).not_nil!)["error"]["type"].as_s.should eq("unauthorized")
      invalid.response.status_code.should eq(401)
      invalid.response.headers["WWW-Authenticate"].should eq("Bearer")

      ENV.delete("OCAWE_API_KEY")
      disabled = generated_workflow_auth_context
      JSON.parse(app.test_generated_workflow_auth_error(disabled).not_nil!)["error"]["type"].as_s.should eq("not_configured")
      disabled.response.status_code.should eq(503)
    ensure
      if previous_key
        ENV["OCAWE_API_KEY"] = previous_key
      else
        ENV.delete("OCAWE_API_KEY")
      end
    end
  end
end
