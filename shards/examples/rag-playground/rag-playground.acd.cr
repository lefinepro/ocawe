struct RagPlaygroundInput
  include JSON::Serializable

  getter text : String?
  getter query : String?
end

struct RagPlaygroundOutput
  include JSON::Serializable

  getter answer : String?
end

workflow "rag-playground" do
  input_type RagPlaygroundInput
  output_type RagPlaygroundOutput

  input_validate Schema::Types.object({
    "text" => Schema::Types.optional(Schema::Types.of(String)),
    "query" => Schema::Types.optional(Schema::Types.of(String)),
  })

  output_validate Schema::Types.object({
    "answer" => Schema::Types.optional(Schema::Types.of(String)),
  })

  skill "rag-ingest-skill"
  rag "rag-ingest", config: {operation: "upsert", vectorStoreName: "memory", indexName: "rag-playground-index"}
  skill "rag-query-skill"
  rag "rag-query", config: {operation: "query", vectorStoreName: "memory", indexName: "rag-playground-index", topK: 5}
end
