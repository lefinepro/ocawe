# Cogni Trigger API Specification

## Scope

This specification defines invocation contracts for the Trigger API and `Cogni::Trigger` client.

## Endpoints

- `POST /v1/triggers/workflows/{id}`
- `POST /v1/triggers/agents/{id}`
- `POST /v1/triggers/skills/{id}`
- `POST /v1/triggers/functions/{id}`

## Request Contracts

### Workflow trigger

Accepted fields:

- `input` or `input_data` (object)
- `resources` (object, optional)
- `run_id` (string, optional)
- `resource_id` (string, optional)

Behavior:

- Starts workflow run using workflow service start semantics.

### Agent trigger

Accepted fields:

- OpenAI-style `messages` and optional `system`
- `model` (optional override)
- `metadata` (object, optional)

Behavior:

- Executes agent generation with workflow/agent metadata propagation.

### Skill trigger

Accepted fields:

- arbitrary payload object

Behavior:

- Invokes skill execution scaffold response contract.

### Function trigger

Accepted fields:

- `input` or `input_data` (object)
- `state` (object, optional)
- `workflow_id` (optional)
- `run_id` (optional)

Behavior:

- Resolves and executes registered function via unified function registry.

## Response Contracts

All endpoints return JSON object payloads.

- Success payload includes stable `id` + `object` discriminator for trigger kind.
- Failure payload uses error envelope:

```json
{"error": {"type": "<error_type>", "message": "<message>"}}
```

## SDK Mapping (`Cogni::Trigger`)

- `trigger.workflow(id).run(payload)` -> workflow trigger endpoint
- `trigger.agent(id).run(payload)` -> agent trigger endpoint
- `trigger.skill(id).run(payload)` -> skill trigger endpoint
- `trigger.function(id).run(payload)` -> function trigger endpoint

## Compatibility

Trigger API keeps strict compatibility-oriented request/response shape strategy and uses existing runtime endpoints as execution backend where applicable.

