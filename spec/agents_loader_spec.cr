require "./spec_helper"
require "file_utils"

describe ACD::Agents::Loader do
  it "loads markdown and org agents with schema blocks" do
    root = File.tempname("agents_loader")
    agents_dir = File.join(root, "agents")
    Dir.mkdir_p(agents_dir)

    begin
      File.write(File.join(agents_dir, "markdown-agent.md"), <<-MD)
---
description: "Markdown agent"
---

Markdown prompt.

<output-ui>
<weather-widget location="{{location}}" temperature="{{temperature}}"></weather-widget>
</output-ui>

```crystal schema:input
Schema::Types.object({"input" => Schema::Types.any()}, strict: false)
```

```crystal schema:output
Schema::Types.object({"last_response" => Schema::Types.of(String)}, strict: false)
```
MD

      File.write(File.join(agents_dir, "org-agent.org"), <<-ORG)
---
description: "Org agent"
---

Org prompt.

#+begin_output ui
<weather-widget location="{{location}}" condition="{{condition}}"></weather-widget>
#+end_output

#+begin_src crystal schema:input
Schema::Types.object({"input" => Schema::Types.any()}, strict: false)
#+end_src

#+begin_src crystal schema:output
Schema::Types.object({"last_response" => Schema::Types.of(String)}, strict: false)
#+end_src
ORG

      agents = ACD::Agents::Loader.new.load_dir(agents_dir)

      agents.map(&.id).should eq(["markdown-agent", "org-agent"])

      markdown_agent = agents.find! { |agent| agent.id == "markdown-agent" }
      markdown_agent.prompt.should eq("Markdown prompt.")
      markdown_agent.input_schema_dsl.not_nil!.should contain("Schema::Types.object")
      markdown_agent.output_schema_dsl.not_nil!.should contain("last_response")
      markdown_agent.output_ui_template.not_nil!.should contain("<weather-widget")

      org_agent = agents.find! { |agent| agent.id == "org-agent" }
      org_agent.prompt.should eq("Org prompt.")
      org_agent.input_schema_dsl.not_nil!.should contain("Schema::Types.object")
      org_agent.output_schema_dsl.not_nil!.should contain("last_response")
      org_agent.output_ui_template.not_nil!.should contain("condition")
    ensure
      FileUtils.rm_rf(root)
    end
  end
end
