# Commands API

Register a local workflow command with Ocawe’s public API:

```crystal
Ocawe::Command.register("set_value", ->(ctx : Ocawe::Workflow::NodeContext) do
  {"status" => JSON.parse("ok".to_json)}
end)
```

Place command source below `plugins/functions/**/*.cr` or the compatibility
path `plugins/commands/**/*.cr`. OCAWE discovers regular files recursively,
canonicalizes them, and loads them in lexical order before workflow execution.
Missing or empty plugin directories remain compatible with projects that do not
use commands.

A command uses the existing registered-function handler contract. A handler can
read `ctx.input_data`, `ctx.state`, and prior node results and returns the same
supported hash or `AgentResult` values as a legacy registered function. Its
result is merged into workflow state. Empty and duplicate command names fail
clearly; legacy `Ocawe::RegistryApi.register_function` collision behavior is
unchanged.

Invoke a registered command with its declared bare name:

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
the command registry performs no network request itself.

Commands are invoked by workflow nodes or application code; input data does not
dynamically dispatch them.

Release and container builds include both plugin paths even when an explicit
container file allowlist omits them. Keep plugin files within the project root.

## `start` and `stop`

`ocawe up` keeps the legacy full-runtime behavior. Use `ocawe start` for the
small runtime API:

```bash
ocawe start ./workflow -d
ocawe stop ./workflow
```

`start` loads the Cawfile at runtime and starts `ocawecore` with `POST /run`,
`POST /stop/:id`, and `GET /metrics`. When a workflow contains Crystal loader
extensions, Ocawe precompiles the workflow runtime before starting it.
Mastra-compatible routes are enabled only when the Cawfile declares
`Api::MastraAPI`. Each start also writes a compressed runtime bundle to
`build/<workflow-id>.runtime.tar.zst`; the bundle contains `ocawecore`, the
Cawfile, and workflow assets.
