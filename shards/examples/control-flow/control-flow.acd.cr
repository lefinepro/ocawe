# Control Flow Example
# Demonstrates while, unless, and until loops in the workflow DSL.

workflow "control-flow" do
  use model: "openai/gpt-4.1"

  # Execute agent unless condition is true
  unless input.skip_preprocessing
    agent "preprocessor"
  end

  # Sequential agent
  agent "analyzer"

  # Conditional with if/else
  if input.needs_translation
    agent "translator"
  else
    agent "passthrough"
  end

  # Parallel execution
  parallel do
    agent "validator"
    agent "formatter"
  end

  # Final agent
  agent "finalizer"
end
