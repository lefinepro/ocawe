# Commands API

Register a local Crystal workflow command with the public facade:

```crystal
Command.register("set_value", ->(ctx : Ocawe::Workflow::NodeContext) : Ocawe::Workflow::RunnableResult do
  {"status" => JSON.parse("ok".to_json)}
end)
```

Place command source below `plugins/commands/**/*.cr`. OCAWE discovers regular
files recursively, canonicalizes them, and loads them in lexical order before
workflow execution. Missing or empty plugin directories are compatible with
projects that do not use commands.

Commands use the existing registered-function handler contract. A handler can
read `ctx.input_data`, `ctx.state`, and prior node results and returns the same
supported hash or `AgentResult` values as a legacy registered function. Its
result is merged into workflow state.

Invoke a registered command with its declared bare name:

```crystal
workflow "commands" do
  set_value
end
```

Conditions can use a quoted command tag path. This reads data only; it never
selects a handler dynamically:

```crystal
if input.command."generate_code"
  agent "coder", model: "openai/gpt-4.1-mini", prompt: "Generate code."
end
```

Missing, `null`, `false`, empty strings, arrays, and objects are falsey. A true
tag runs the existing agent node and keeps its normal `agent_result` and
`last_response` fields. Use a deterministic mock model in tests and examples;
the Commands API performs no network request itself.

Duplicate or empty command names fail registration clearly. The legacy
`Ocawe::RegistryApi.register_function` API remains supported and retains its
existing collision behavior. Do not use `Command.call` or dispatch a command
from input data.

Release and container builds include `plugins/commands` even when an explicit
container file allowlist omits it. Keep plugin files within the project root.
