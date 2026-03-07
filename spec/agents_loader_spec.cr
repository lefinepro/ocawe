require "./spec_helper"
require "file_utils"

describe ACD::Agents::Loader do
  it "loads voice and guardrails frontmatter plus crystal schema blocks" do
    root = "/tmp/cogni_agents_loader_#{Random.rand(1_000_000)}"
    Dir.mkdir_p(root)

    begin
      File.write(
        File.join(root, "agent-one.md"),
        <<-MD
---
description: "Agent with voice and guardrails"
model: "openai/gpt-4.1-mini"
voice:
  voice_operator: "openai"
  speaker: "alloy"
guardrails:
  input:
    blocked_terms: ["forbidden"]
  output:
    max_length: 1000
---
You are a concise assistant.

```crystal schema:input
Schema::Types.object({"task" => Schema::Types.of(String)})
```

```crystal schema:output
Schema::Types.object({"answer" => Schema::Types.of(String)})
```
MD
      )

      loaded = ACD::Agents::Loader.new.load_dir(root)
      loaded.size.should eq(1)
      agent = loaded.first

      agent.model.should eq("openai/gpt-4.1-mini")
      agent.voice_config.not_nil!["voice_operator"].as_s.should eq("openai")
      agent.guardrails_config.not_nil!["input"].as_h?.should_not be_nil
      agent.input_schema_dsl.not_nil!.includes?("Schema::Types.object").should eq(true)
      agent.output_schema_dsl.not_nil!.includes?("Schema::Types.object").should eq(true)
      agent.prompt.includes?("schema:input").should eq(false)
      agent.prompt.includes?("schema:output").should eq(false)
    ensure
      FileUtils.rm_rf(root)
    end
  end
end
