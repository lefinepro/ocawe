# Commands API validation

This record maps the Commands API task branches to reproducible focused checks.
All fixtures use local deterministic data; no model, federation, or network
request is required at runtime.

| Task | Focused command | Result |
| --- | --- | --- |
| TASK-01 | `crystal spec spec/command_api_spec.cr` | 4 examples, 0 failures |
| TASK-02 | `crystal spec spec/command_plugin_discovery_spec.cr` | 3 examples, 0 failures |
| TASK-03 | `crystal spec spec/command_invocation_spec.cr` | 2 examples, 0 failures |
| TASK-04 | `crystal spec spec/workflow_condition_spec.cr` | 3 examples, 0 failures |
| TASK-05 | `crystal spec spec/command_tag_agent_spec.cr` | 2 examples, 0 failures |
| TASK-06 | `crystal spec spec/command_plugin_build_spec.cr` | 1 example, 0 failures |
| TASK-07 | `crystal spec spec/command_docs_example_spec.cr` | 1 example, 0 failures |

The complete suite was run from this branch and exited successfully. The
release/Nix check remains the final environment-dependent command:

```sh
crystal spec
nix flake check
```

Review checks:

- `Ocawe::Command.register` is the public command registration API.
- `set_value` is registered through the Commands API.
- Plugin paths are canonicalized, sorted, and confined to the project root.
- Bare invocation remains the existing function-registry fallback.
- `input.command."generate_code"` is data lookup and never dispatches a handler.
- Explicit container file lists include command plugin directories automatically.
- The example has no explicit plugin `require` and uses the mock model fixture.
