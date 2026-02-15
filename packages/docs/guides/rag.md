# RAG Workflow

RAG is used as a workflow DSL node.

Example bundle: `shards/examples/rag-playground`

Directive:
- `rag "rag-node-id", config: { ... }`

Mastra-compatible keys supported by Crystal RAG runtime:
- `vectorStoreName` (alias: `vector_store_name`)
- `indexName` (alias: `index_name`)
- `queryText` (aliases: `query_text`, `query`)
- `topK` (alias: `top_k`)
- `filter`
- `operation` (`"upsert"` or `"query"`)

Input compatibility:
- Upsert: `text`, `document`, `documents`, or `chunks`
- Query: `queryText`/`query`

Output compatibility:
- `relevantContext`
- `sources`
- `answer`
- plus workflow-native fields like `rag_status`, `documents_count`, `rag_documents`

Example:

```crystal
workflow "rag-playground" do
  rag "rag-ingest", config: {operation: "upsert", vectorStoreName: "memory", indexName: "docs-index"}
  rag "rag-query", config: {operation: "query", vectorStoreName: "memory", indexName: "docs-index", topK: 5}
end
```
