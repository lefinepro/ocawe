# Local Functions

Register a local Crystal workflow function with the registry API:

```crystal
Ocawe::RegistryApi.register_function("set_value") do |ctx|
  {"status" => JSON.parse("ok".to_json)}
end
```

Place function source below `plugins/functions/**/*.cr`. OCAWE discovers regular
files recursively, canonicalizes them, and loads them in lexical order before
workflow execution. Missing or empty plugin directories are compatible with
projects that do not use functions.

A function uses the existing registered-function handler contract. A handler can
read `ctx.input_data`, `ctx.state`, and prior node results and returns the same
supported hash or `AgentResult` values as a legacy registered function. Its
result is merged into workflow state.

Invoke a registered function with its declared bare name:

```crystal
workflow "commands" do
  set_value
end
```

Prompts can use the `#name` convention. A quoted input path reads data only; it never
selects a handler dynamically:

```crystal
if input.command."generate_code"
  agent "coder", model: "openai/gpt-4.1-mini", prompt: "Generate code."
end
```

Missing, `null`, `false`, empty strings, arrays, and objects are falsey. A true
tag runs the existing agent node and keeps its normal `agent_result` and
`last_response` fields. Use a deterministic mock model in tests and examples;
the function registry performs no network request itself.

Duplicate or empty function names fail registration clearly. The registry
retains its existing collision behavior. Functions are invoked by workflow
nodes or application code; input data does not dynamically dispatch them.

Release and container builds include `plugins/functions` even when an explicit
container file allowlist omits it. Keep plugin files within the project root.
