# Unified Resource Management Example
# Demonstrates the new unified `use` attribute for models, skills, and tools.

workflow "unified-resources" do
  # Combined resource declaration
  use model: "openai/gpt-4.1",
      skill: ["translation", "summarization"],
      tool: ["http-client"]

  # Sequential agents with shared resources
  agent "analyzer"
  agent "processor"

  # Parallel execution block
  parallel do
    agent "translator"
    agent "summarizer"
  end

  # Final synthesis
  agent "synthesizer"
end
