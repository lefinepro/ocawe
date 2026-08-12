# Cawfile pipeline reference

Use this reference for repository-native syntax and reproducibility decisions. Prefer current source and examples if this file and the checked-out Ocawe version differ.

## Bundle shape

The preferred layout is:

```text
pipeline/
├── Cawfile
├── agents/                 # model-backed agent definitions
├── plugins/functions/      # Crystal function registrations
├── skills/                 # Ocawe runtime skills, not Codex skills
└── tools/                  # local executable helpers
```

A root or bundle-local `Cawfile` may contain settings, a container declaration, Crystal types, annotations, multiple workflows, and tests.

## Contract-first skeleton

```crystal
settings do
  data.adapter = "memory"
  port = 4111
end

struct PipelineInput
  include JSON::Serializable
  getter input : String?
end

struct PipelineOutput
  include JSON::Serializable
  getter last_response : String?
  getter status : String?
end

@[Validate(PipelineInput, PipelineOutput)]
workflow "pipeline" do
  transform_input
end

test "returns deterministic output" do
  assert "pipeline", input: "example", equality: "example"
end
```

Register local functions below `plugins/functions/**/*.cr`:

```crystal
Ocawe::RegistryApi.register_function("transform_input") do |ctx|
  value = ctx.input_data["input"]?.try(&.as_s?) || ""
  {
    "last_response" => JSON.parse(value.to_json),
    "status" => JSON.parse("ok".to_json),
  }
end
```

Function files are discovered recursively in lexical order. Keep compatibility files under `plugins/commands` only when maintaining an existing bundle.

## Supported composition

Use these forms already exercised by Ocawe examples and specs:

- `agent "id", model: "provider/model", prompt: "..."`
- `skill "id", agent: "agent-id"`
- `exec "tools/script.sh", runtime: {shell: "bash"}`
- `exec "codex", runtime: {acp: {command: "codex", args: ["--server"]}}`
- `get`, `post`, and `put` with explicit IDs for later `step["id"]` access
- `rag`, `voice`, and `suspend`
- `if`, `elsif`, `else`, `unless`, `parallel`, `while`, `until`, and `loop`
- `@[Model("provider/model")]`, `@[Service]`, `@[Logger(...)]`, and `@[Workspace(...)]`

Use a root `container do` block when the runtime needs packages or bundle files:

```crystal
container do
  packages = ["bash", "jq"]
  files = ["agents", "plugins/functions", "skills", "tools"]
end
```

`packages` resolve through Nix. The enclosing flake lock is the reproducibility boundary; keep it committed. `files` is an allowlist, so include every runtime asset. Ocawe also includes function-plugin directories for compatibility, but declare them for clarity.

## Reproducibility rules

### Inputs and outputs

- Treat the request payload as the only variable input.
- Validate public workflows with concrete serializable types.
- Return stable keys and types from every local function.
- Do not derive behavior from undeclared environment variables.

### Models and network

- Specify model IDs explicitly; never rely on provider defaults.
- Model IDs do not make generated text deterministic. Use `COGNICORE_MOCK_LLM=1` in tests and describe live-model checks as integration checks.
- Stub HTTP dependencies locally for tests. Set explicit timeouts and validate response shapes in production pipelines.
- Treat `git+https` and `git+ssh` workflow execution as mutable unless the checked-out Ocawe version supports and uses an immutable revision.

### Scripts and tools

- Store scripts under the bundle, invoke them with relative paths, and declare the runtime shell.
- Use `set -euo pipefail` in Bash helpers.
- Sort filesystem traversal and serialized collections when order affects output.
- Avoid ambient current time, randomness, locale, user home, and global caches. Accept required values as inputs or inject fixed test values.
- Keep secrets outside source and output. Pass only named secret references or environment variables supplied at runtime.

### State and control flow

- Use stable node IDs where later expressions read `step["id"]`.
- Parallelize only independent work. Parallel branches must not rely on ordering or overwrite the same state key.
- Bound loops through input/state conditions and the runtime's iteration limit; test both exit and failure paths.
- Mark only genuine daemons/watchers with `@[Service]`.

## Validation sequence

From an Ocawe checkout:

```bash
.agents/skills/ocawe-write-pipelines/scripts/check_pipeline.sh PATH_TO_BUNDLE
nix develop --command crystal spec SPEC_FILES_FOR_THE_CHANGE
nix develop --command ./bin/ameba
```

For executable bundle tests, run a mock-backed runtime in one terminal, then:

```bash
COGNICORE_MOCK_LLM=1 ocawe up PATH_TO_BUNDLE
ocawe test PATH_TO_BUNDLE
```

`ocawe test` needs the runtime endpoint. It is not a parser-only check. Run real API/model tests separately and label them as integration tests.
