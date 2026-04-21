# Examples

Use the example bundles to learn one Cogni concept at a time.

## Run All Examples

```bash
./build/cogni up --port 4111 --workflows-root ./shards/examples
```

## Core Example Bundles

- `agents-example`: basic agent execution and model usage
- `skills-example`: skills bound to agent context
- `workflow-example`: workflow composition and schema refs
- `control-flow`: explicit control-flow nodes and staged execution
- `voice-playground`: voice DSL and voice frontmatter
- `rag-playground`: RAG orchestration through workflow nodes
- `simple-model-test`: model override behavior
- `full-capabilities`: broad survey of supported directives
- `config-example`: Crystal-native runtime config template

The primary learning path is through these `.acd.cr` bundles under `shards/examples`.

## Programmatic Examples

- `src/control_flow_workflow_example.cr`: lower-level programmatic control flow and events
- `src/custom_provider_example.cr`: custom provider registration and `AI::Client` wiring

These are framework-oriented examples, not the primary authoring format for end-user workflows.

## Workspace Extension Example

`shards/docker-git` demonstrates a workflow-centered project that uses workspace annotations and workspace extension APIs.

Run it with:

```bash
crystal run shards/docker-git/src/docker_git.cr -- --port 4222
```

## Important Notes

- Use `exec "path_or_inline", runtime: {...}` for external execution.
- Use unified step types such as `agent_codex`, `agent_cliproxy`, and `agent_opencode` for external agent node kinds.
- Use `Cogni::RegistryApi.node_kind` and `Cogni::RegistryApi.resource` for new runtime extensions.
