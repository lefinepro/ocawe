---
name: "Assistant"
description: "Simple assistant"
---

You are a concise assistant. Help with software development tasks efficiently.

#+begin_src crystal schema:input
Schema::Types.object({"input" => Schema::Types.of(JSON::Any)}, strict: false)
#+end_src

#+begin_src crystal schema:output
Schema::Types.object({"last_response" => Schema::Types.of(String)}, strict: false)
#+end_src
