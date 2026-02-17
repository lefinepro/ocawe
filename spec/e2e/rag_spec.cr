require "./e2e_spec_helper"

# E2E Tests for RAG (Retrieval-Augmented Generation) Operations
#
# Tests RAG workflow patterns:
# - RAG upsert (ingestion) operations
# - RAG query operations
# - RAG playground patterns

describe "E2E: RAG Operations" do
  describe "rag-playground" do
    it "creates workflow with RAG nodes" do
      # Simulates rag-playground workflow structure
      workflow = CogniCore::Workflow.create_workflow("rag-playground", "RAG test")
      workflow
        .rag("rag-ingest", config: {
          "operation"       => json_str("upsert"),
          "vectorStoreName" => json_str("memory"),
          "indexName"       => json_str("rag-playground-index"),
        })
        .rag("rag-query", config: {
          "operation"       => json_str("query"),
          "vectorStoreName" => json_str("memory"),
          "indexName"       => json_str("rag-playground-index"),
          "topK"            => JSON.parse(5.to_json),
        })
        .commit

      workflow.nodes.size.should eq(2)
      workflow.nodes[0].kind.should eq(CogniCore::Workflow::NodeKind::Rag)
      workflow.nodes[1].kind.should eq(CogniCore::Workflow::NodeKind::Rag)
    end

    it "executes RAG upsert operation" do
      workflow = CogniCore::Workflow.create_workflow("rag-upsert-test", "RAG upsert test")
      workflow
        .rag("ingest", config: {
          "operation"       => json_str("upsert"),
          "vectorStoreName" => json_str("memory"),
          "indexName"       => json_str("test-index"),
        })
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("rag-upsert-test")
      result = run.start(input_data: {
        "documents" => JSON.parse(["Test document one", "Test document two"].to_json),
      })
      result.status.should eq("success")
      result.state.not_nil!["operation"].as_s.should eq("upsert")
    end

    it "executes RAG query operation" do
      workflow = CogniCore::Workflow.create_workflow("rag-query-test", "RAG query test")
      workflow
        .rag("query", config: {
          "operation"       => json_str("query"),
          "vectorStoreName" => json_str("memory"),
          "indexName"       => json_str("test-index"),
          "topK"            => JSON.parse(3.to_json),
        })
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("rag-query-test")
      result = run.start(input_data: {
        "queryText" => json_str("test query"),
        "topK"      => JSON.parse(3.to_json),
      })
      result.status.should eq("success")
      result.state.not_nil!["operation"].as_s.should eq("query")
    end
  end

  describe "RAG upsert and query workflow" do
    it "performs RAG upsert and query operations" do
      workflow = CogniCore::Workflow.create_workflow("e2e-rag", "RAG operations")
      workflow
        .rag("ingest", config: {
          "operation"       => json_str("upsert"),
          "vectorStoreName" => json_str("memory"),
          "indexName"       => json_str("e2e-test-index"),
        })
        .rag("query", config: {
          "operation"       => json_str("query"),
          "vectorStoreName" => json_str("memory"),
          "indexName"       => json_str("e2e-test-index"),
          "topK"            => JSON.parse(5.to_json),
        })
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("e2e-rag")
      result = run.start(input_data: {
        "documents" => JSON.parse(["Document one", "Document two"].to_json),
        "queryText" => json_str("Document"),
        "topK"      => JSON.parse(3.to_json),
      })

      result.status.should eq("success")
      result.state.not_nil!["operation"].as_s.should eq("query")
      result.state.not_nil!["sources"].as_a.size.should be > 0
    end
  end

  describe "RAG in full workflows" do
    it "combines RAG with approval step" do
      workflow = CogniCore::Workflow.create_workflow("rag-approval-test", "RAG with approval")
      workflow
        .then(CogniCore::Workflow::WorkflowNode.new("setup", CogniCore::Workflow::NodeKind::Control) do |_ctx|
          CogniCore::Workflow::WorkflowNodeResult.continue({"prepared" => json_bool(true)})
        end)
        .rag("rag", config: {
          "operation"       => json_str("query"),
          "vectorStoreName" => json_str("memory"),
          "indexName"       => json_str("test-index"),
        })
        .suspend("confirm", reason: "Confirm RAG results")
        .commit

      engine = CogniCore::Workflow::Engine.new
      engine.register(workflow)

      run = engine.create_run("rag-approval-test")
      result = run.start(input_data: {"queryText" => json_str("test query")})
      result.status.should eq("suspended")
      result.resume_labels.should eq(["confirm"])
    end
  end
end
