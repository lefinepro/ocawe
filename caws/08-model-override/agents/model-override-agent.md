---
name: "Model Override Agent"
description: "Agent with model override"
model: "openai/gpt-5"
---

You are a helpful assistant using GPT-5.

#+begin_src crystal schema:input
Schema::Types.object({"input" => Schema::Types.of(JSON::Any)}, strict: false)
#+end_src

#+begin_src crystal schema:output
Schema::Types.object({"last_response" => Schema::Types.of(String)}, strict: false)
#+end_src
