# Examples

Examples live under `shards/examples` and are designed for direct reuse.

## Run all examples

```bash
./build/cogni up --port 4111 --workflows-root ./shards/examples --fallback-workflows-root ./shards/examples
```

## Bundles

- `agents-example`: agent + model basics
- `skills-example`: skills with agent context
- `workflow-example`: agent + custom node + schema refs
- `voice-playground`: voice DSL + voice frontmatter
- `rag-playground`: rag DSL + skill choreography
- `simple-model-test`: model override behavior
- `full-capabilities`: all currently supported `.acd.cr` directives
- `config-example`: Crystal-native `AppConfig` template

## Notes

- `tool tool_*` syntax is supported, but crystal tool functions must be registered through `CogniCore::Workflow.register_tool`.
- External tool syntax (`tool "path", runtime: { ... }`) works out of the box when script paths are valid.
