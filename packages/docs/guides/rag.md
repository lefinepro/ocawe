# RAG (Retrieval-Augmented Generation)

Build knowledge-enhanced agents with document processing, embedding, and vector search. RAG enables agents to retrieve relevant context from your documents and data.

## What is RAG?

RAG (Retrieval-Augmented Generation) enhances LLM responses by retrieving relevant information from a knowledge base before generation. This enables:

- **Accurate, grounded responses** - Based on your documents
- **Up-to-date information** - Without retraining models
- **Source attribution** - Know where answers come from
- **Domain expertise** - Specialized knowledge for your use case

## When to Use RAG

**Use RAG when:**
- You need answers based on specific documents
- You want to ground LLM responses in facts
- You have a large knowledge base to search
- You need source attribution for answers
- Your data changes frequently

**Don't use RAG when:**
- Simple keyword search is sufficient
- You need general knowledge (LLM already knows it)
- Your dataset is very small (< 10 documents)

## RAG Workflow Node

RAG is used as a workflow DSL node for document ingestion and retrieval.

### Basic RAG Workflow

```crystal
workflow "rag-qa" do
  # Ingest documents into vector store
  rag "ingest",
    config: {
      operation: "upsert",
      vectorStoreName: "docs",
      indexName: "knowledge-base"
    }
  
  # Query for relevant context
  rag "retrieve",
    config: {
      operation: "query",
      vectorStoreName: "docs",
      indexName: "knowledge-base",
      queryText: input.question,
      topK: 5
    }
  
  # Agent generates answer with retrieved context
  agent "qa-agent",
    prompt: "Answer the question using the provided context"
end
```

## RAG Configuration

### Supported Configuration Keys

**Mastra-compatible keys**:
- `vectorStoreName` (alias: `vector_store_name`) - Vector store identifier
- `indexName` (alias: `index_name`) - Index/collection name
- `queryText` (aliases: `query_text`, `query`) - Search query
- `topK` (alias: `top_k`) - Number of results to return
- `filter` - Metadata filters for search
- `operation` - Operation type: `"upsert"` or `"query"`

### Operation Types

#### Upsert Operation

Indexes documents into the vector store:

```crystal
rag "ingest",
  config: {
    operation: "upsert",
    vectorStoreName: "docs",
    indexName: "knowledge-base"
  }
```

**Input formats**:
- `text` - Single text string
- `document` - Single document object
- `documents` - Array of documents
- `chunks` - Pre-chunked text segments

**Example input**:

```json
{
  "documents": [
    {
      "id": "doc1",
      "content": "Crystal is a statically-typed programming language...",
      "metadata": {
        "source": "crystal-docs",
        "category": "introduction"
      }
    },
    {
      "id": "doc2",
      "content": "Crystal's syntax is inspired by Ruby...",
      "metadata": {
        "source": "crystal-docs",
        "category": "syntax"
      }
    }
  ]
}
```

#### Query Operation

Retrieves relevant documents:

```crystal
rag "retrieve",
  config: {
    operation: "query",
    vectorStoreName: "docs",
    indexName: "knowledge-base",
    queryText: input.question,
    topK: 5,
    filter: {
      category: "introduction"
    }
  }
```

**Output format**:

```json
{
  "relevantContext": "Combined text from top results",
  "sources": [
    {
      "id": "doc1",
      "content": "...",
      "score": 0.95,
      "metadata": {...}
    }
  ],
  "rag_status": "success",
  "documents_count": 5
}
```

## Complete RAG Pipeline

### Document Processing and Q&A

```crystal
workflow "document-qa" do
  # Step 1: Load documents from file
  exec "tools/load_documents.sh",
    runtime: {shell: "bash"},
    env: {
      DOCS_PATH: input.docs_path
    }
  
  # Step 2: Ingest into vector store
  rag "ingest",
    config: {
      operation: "upsert",
      vectorStoreName: "docs",
      indexName: "user-docs"
    }
  
  # Step 3: Query for relevant context
  rag "retrieve",
    config: {
      operation: "query",
      vectorStoreName: "docs",
      indexName: "user-docs",
      queryText: input.question,
      topK: 3
    }
  
  # Step 4: Generate answer with context
  agent "qa-agent",
    prompt: """
      Answer the question based on the following context.
      If the answer is not in the context, say so.
      
      Context: #{state.retrieve_relevantContext}
      
      Question: #{input.question}
      
      Provide sources for your answer.
    """
end
```

### Multi-Source RAG

Query multiple knowledge bases:

```crystal
workflow "multi-source-rag" do
  parallel do
    # Search documentation
    rag "docs-search",
      config: {
        operation: "query",
        vectorStoreName: "docs",
        indexName: "documentation",
        queryText: input.query,
        topK: 3
      }
    
    # Search code examples
    rag "code-search",
      config: {
        operation: "query",
        vectorStoreName: "code",
        indexName: "examples",
        queryText: input.query,
        topK: 3
      }
    
    # Search FAQs
    rag "faq-search",
      config: {
        operation: "query",
        vectorStoreName: "support",
        indexName: "faqs",
        queryText: input.query,
        topK: 2
      }
  end
  
  # Synthesize results from all sources
  agent "synthesizer",
    prompt: """
      Synthesize information from multiple sources:
      
      Documentation: #{state.docs_search_relevantContext}
      Code Examples: #{state.code_search_relevantContext}
      FAQs: #{state.faq_search_relevantContext}
      
      Provide a comprehensive answer with source attribution.
    """
end
```

## Advanced RAG Patterns

### Metadata Filtering

Filter results by metadata:

```crystal
workflow "filtered-rag" do
  rag "retrieve",
    config: {
      operation: "query",
      vectorStoreName: "docs",
      indexName: "knowledge-base",
      queryText: input.question,
      topK: 5,
      filter: {
        category: "technical",
        language: "en",
        version: "latest"
      }
    }
  
  agent "qa-agent"
end
```

### Iterative RAG

Refine queries based on initial results:

```crystal
workflow "iterative-rag" do
  # Initial query
  rag "initial-search",
    config: {
      operation: "query",
      vectorStoreName: "docs",
      indexName: "knowledge-base",
      queryText: input.question,
      topK: 3
    }
  
  # Agent analyzes results and generates refined query
  agent "query-refiner",
    prompt: """
      Based on these initial results, refine the search query.
      Initial results: #{state.initial_search_relevantContext}
      Original question: #{input.question}
    """
  
  # Refined search
  rag "refined-search",
    config: {
      operation: "query",
      vectorStoreName: "docs",
      indexName: "knowledge-base",
      queryText: state.query_refiner_refined_query,
      topK: 5
    }
  
  # Final answer generation
  agent "qa-agent",
    prompt: "Generate comprehensive answer using refined results"
end
```

### Hybrid Search

Combine semantic and keyword search:

```crystal
workflow "hybrid-search" do
  parallel do
    # Semantic search via RAG
    rag "semantic-search",
      config: {
        operation: "query",
        vectorStoreName: "docs",
        indexName: "knowledge-base",
        queryText: input.question,
        topK: 5
      }
    
    # Keyword search via tool
    exec "tools/keyword_search.sh",
      runtime: {shell: "bash"},
      env: {
        QUERY: input.question,
        INDEX: "knowledge-base"
      }
  end
  
  # Agent combines both result sets
  agent "result-ranker",
    prompt: """
      Rank and combine results from:
      1. Semantic search: #{state.semantic_search_sources}
      2. Keyword search: #{state.keyword_search_results}
      
      Select the most relevant information and generate an answer.
    """
end
```

## Vector Store Integration

### Supported Vector Stores

Ocawe supports multiple vector store backends:

- In-memory (default, for development)
- PostgreSQL with pgvector
- Pinecone
- Qdrant
- Chroma
- MongoDB with vector search

### Configuration

**In-memory** (default):

```crystal
rag "ingest",
  config: {
    vectorStoreName: "memory",
    indexName: "temp-index"
  }
```

**PostgreSQL with pgvector**:

```crystal
rag "ingest",
  config: {
    vectorStoreName: "postgres",
    indexName: "knowledge_base",
    connectionString: state.resources.database_url
  }
```

**Pinecone**:

```crystal
rag "ingest",
  config: {
    vectorStoreName: "pinecone",
    indexName: "prod-kb",
    apiKey: state.resources.pinecone_api_key,
    environment: "us-west1-gcp"
  }
```

## Document Processing

### Document Chunking

Split large documents into chunks:

```crystal
workflow "document-processing" do
  # Load document
  exec "tools/load_document.sh",
    runtime: {shell: "bash"}
  
  # Chunk document
  exec "tools/chunk_text.py",
    runtime: {
      command: "python3",
      args: ["--chunk-size", "512", "--overlap", "50"]
    }
  
  # Ingest chunks
  rag "ingest-chunks",
    config: {
      operation: "upsert",
      vectorStoreName: "docs",
      indexName: "chunked-docs"
    }
end
```

### Embedding Models

Use different embedding models:

```crystal
rag "ingest",
  config: {
    operation: "upsert",
    vectorStoreName: "docs",
    indexName: "knowledge-base",
    embeddingModel: "openai/text-embedding-3-small"
  }
```

**Supported models**:
- OpenAI: `openai/text-embedding-3-small`, `openai/text-embedding-3-large`
- Local models: `sentence-transformers/all-MiniLM-L6-v2`
- Custom endpoints

## RAG with Agents

### Context-Aware Agent

```crystal
workflow "rag-agent" do
  # Retrieve relevant context
  rag "retrieve",
    config: {
      operation: "query",
      vectorStoreName: "docs",
      indexName: "knowledge-base",
      queryText: input.question,
      topK: 3
    }
  
  # Agent with retrieved context
  agent "expert-agent",
    prompt: """
      You are a domain expert. Answer questions using the provided context.
      
      Context:
      #{state.retrieve_relevantContext}
      
      Sources:
      #{state.retrieve_sources.map { |s| "- #{s["metadata"]["source"]}" }.join("\n")}
      
      Question: #{input.question}
      
      Instructions:
      1. Answer based on the context
      2. Cite sources
      3. If unsure, say so
    """
end
```

### Conversational RAG

Maintain conversation history with RAG:

```crystal
workflow "conversational-rag" do
  # Query based on conversation history
  agent "query-rewriter",
    prompt: """
      Rewrite the user's question considering conversation history.
      History: #{input.conversation_history}
      Question: #{input.question}
    """
  
  # Retrieve relevant context
  rag "retrieve",
    config: {
      operation: "query",
      vectorStoreName: "docs",
      indexName: "knowledge-base",
      queryText: state.query_rewriter_rewritten_query,
      topK: 5
    }
  
  # Generate answer
  agent "conversational-agent",
    prompt: """
      Continue the conversation using retrieved context.
      Context: #{state.retrieve_relevantContext}
      History: #{input.conversation_history}
      Question: #{input.question}
    """
end
```

## Best Practices

### 1. Chunk Documents Appropriately

**Good** - Semantic chunks (512-1024 tokens):

```python
# Chunk by paragraphs with overlap
chunks = chunk_text(document, chunk_size=512, overlap=50)
```

**Bad** - Too small or too large:

```python
# Too small - loses context
chunks = chunk_text(document, chunk_size=50)

# Too large - reduces retrieval precision
chunks = chunk_text(document, chunk_size=5000)
```

### 2. Use Metadata for Filtering

```json
{
  "document": {
    "content": "...",
    "metadata": {
      "source": "product-docs",
      "version": "2.0",
      "category": "api-reference",
      "language": "en",
      "updated_at": "2024-06-10"
    }
  }
}
```

### 3. Optimize topK

Start with 3-5 results and adjust based on quality:

```crystal
# For precise questions
topK: 3

# For complex questions
topK: 10

# For exploratory queries
topK: 20
```

### 4. Provide Source Attribution

```crystal
agent "qa-agent",
  prompt: """
    Answer the question and cite your sources.
    
    Format:
    Answer: [Your answer]
    
    Sources:
    #{state.retrieve_sources.map { |s| "- #{s["id"]}: #{s["metadata"]["title"]}" }.join("\n")}
  """
```

### 5. Handle No Results

```crystal
workflow "safe-rag" do
  rag "retrieve",
    config: {
      operation: "query",
      vectorStoreName: "docs",
      queryText: input.question,
      topK: 5
    }
  
  if state.retrieve_documents_count == 0
    agent "fallback-agent",
      prompt: "No relevant documents found. Provide general guidance."
  else
    agent "qa-agent",
      prompt: "Answer using retrieved context"
  end
end
```

## Example Bundle

Explore the complete RAG example:

```bash
# Located in project
shards/examples/rag-playground
```

## API Integration

### Trigger RAG Workflow

```bash
curl -X POST http://localhost:4111/v1/triggers/workflows/rag-qa \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "question": "How do I use RAG in Ocawe?",
      "docs_path": "/path/to/docs"
    }
  }'
```

### Response

```json
{
  "run_id": "run-abc123",
  "status": "completed",
  "output": {
    "answer": "To use RAG in Ocawe...",
    "sources": [
      {
        "id": "doc1",
        "content": "...",
        "score": 0.95
      }
    ],
    "confidence": 0.92
  }
}
```

## Next Steps

- **[Agents Guide](/guides/agents)** - Build intelligent agents
- **[Workflows Guide](/guides/workflows)** - Orchestrate RAG pipelines
- **[Tools Guide](/guides/tools)** - Integrate external data sources
- **[Voice Guide](/guides/voice)** - Combine RAG with voice
- **[Examples](/guides/examples)** - Explore RAG examples
