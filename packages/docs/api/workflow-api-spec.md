# Cogni Declarative Workflow API Specification

## Scope

This specification defines the declarative workflow-building API exposed by `Cogni::Workflow`.

## Core Type

- `Cogni::Workflow < CogniCore::Workflow::WorkflowDefinition`
- Factory: `Cogni::Workflow.build(id, description = nil)`

## Node Construction

Supported declarative methods:

- `use(model:, skill:, tool:)`
- `agent(...)`
- `skill(...)`
- `run(ref, runtime: nil, env: nil, params: nil, input_schema: nil, output_schema: nil)`
- `voice(...)`
- `rag(...)`
- `suspend(...)`
- `parallel(nodes)`
- `then(node)`
- `while_do(condition, nodes, max_iterations = 100)`
- `until_do(condition, nodes, max_iterations = 100)`
- `loop_do(nodes, max_iterations = 100)`
- `foreach(node)`
- `wait_for_event(...)`
- `send_event(...)`
- `sleep(...)`
- `sleep_until(...)`

Removed methods:

- `tool(...)`
- `fn(...)`

## `run` Resolution

`run(ref, ...)` resolves execution as follows:

1. If `runtime` is provided: execute external script.
  - `ref` is treated as a script path when found under workflow root/global tools root.
  - otherwise `ref` is treated as inline script text.
2. If `runtime` is omitted: resolve `ref` as registered function name/alias/indexed name.

External run stdout must be a JSON object.

## Function Registration and Collision Rules

Function registry is case-insensitive normalized.

- Base-name lookup prioritizes system functions.
- User collisions are indexed: `name:1`, `name:2`, ...
- Explicit aliases are supported and resolved directly.

## Input Envelope Semantics

For `agent` and `run` nodes:

```json
{"input": <previous-step-output-or-init>, "context": {"workflow_id": "...", "run_id": "...", "state": {...}}}
```

If `params` metadata exists for `run`, those fields are merged at top-level of the run input envelope.

## Loop Semantics

- `while_do`: executes body while condition evaluates `true`.
- `until_do`: executes body while condition evaluates `false`.
- `loop_do`: executes body until max iterations or non-continue result.
- Default loop cap is `100`.

