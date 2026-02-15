# Voice Workflow

Voice is used as a workflow DSL node.

Example bundle: `shards/examples/voice-playground`

Directive:
- `voice "voice-node-id"`

Voice execution is DSL-first and does not require startup auto-registered voice tool modules.

## Agent Frontmatter Voice

Agent markdown frontmatter can define voice defaults:

```yaml
voice:
  voice_operator: "openai"
  speaker: "alloy"
```

When a workflow runs an `agent` node, that voice config becomes the default for downstream `voice` nodes unless overridden by inline `config: {...}`.
