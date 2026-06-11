---
name: "Main Agent"
description: "General-purpose assistant"
model: "cliproxyapi/qwen3-coder-plus"
---

You are a general-purpose assistant. Help with software development tasks.

#+begin_src crystal schema:input
Schema::Types.object({"input" => Schema::Types.of(JSON::Any)}, strict: false)
#+end_src

#+begin_src crystal schema:output
Schema::Types.object({"last_response" => Schema::Types.of(String)}, strict: false)
#+end_src
