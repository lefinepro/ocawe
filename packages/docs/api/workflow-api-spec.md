# Cogni Workflow API Specification

## Scope

This specification defines the workflow-building API exposed by `Cogni::Workflow`.

## Core Type

- `Cogni::Workflow::WorkflowDefinition`
- Factory: `Cogni::Workflow.build(id, description = nil)`

## Node Construction

Supported workflow methods:

- `agent(...)`
- `skill(...)`
- `exec(ref, runtime: nil, env: nil, attributes: nil, input_schema: nil, output_schema: nil)`
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

## `exec` Resolution

`exec(ref, ...)` resolves execution as follows:

1. If `runtime` is provided: execute external script.
  - `ref` is treated as a script path when found under workflow root/global tools root.
  - otherwise `ref` is treated as inline script text.
2. If `runtime` is omitted, only `mcp:` refs are allowed.
3. Internal Crystal logic in workflows must be represented as internal function-name nodes (for example `agent_codex`).

External exec stdout must be a JSON object.

## Function Registration and Collision Rules

Function registry is case-insensitive normalized.

- Base-name lookup prioritizes system functions.
- User collisions are indexed: `name:1`, `name:2`, ...
- Explicit aliases are supported and resolved directly.

## Input Envelope Semantics

For `agent`, `exec`, and internal function-name (`custom`) nodes:

```json
{"input": <previous-step-output-or-init>, "context": {"workflow_id": "...", "run_id": "...", "state": {...}}}
```

If `attributes` metadata exists for `exec` or internal function-name nodes, those fields are merged at top-level of the input envelope.

## Loop Semantics

- `while_do`: executes body while condition evaluates `true`.
- `until_do`: executes body while condition evaluates `false`.
- `loop_do`: executes body until max iterations or non-continue result.
- Default loop cap is `100`.
