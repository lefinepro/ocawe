---
name: ocawe-write-pipelines
description: Design, implement, review, and validate reproducible Ocawe pipelines using the repository-native Cawfile DSL. Use when Codex is asked to create or modify an Ocawe workflow bundle, convert an informal process into a Cawfile, add deterministic pipeline tests, package local agents/functions/tools, or audit a pipeline for mutable inputs, hidden dependencies, and non-repeatable execution.
---

# Write Ocawe Pipelines

Build Cawfile bundles whose inputs, execution order, dependencies, outputs, and checks are explicit and repeatable.

## Authoring workflow

1. Inspect the target repository and its nearest `AGENTS.md`. Locate the active `Cawfile`, bundle assets, and relevant specs before editing.
2. Read [references/cawfile-pipelines.md](references/cawfile-pipelines.md) for supported DSL and reproducibility rules. Re-check Ocawe source or current examples when using a directive not covered there.
3. Define the contract first:
   - Add `JSON::Serializable` input and output structs.
   - Attach `@[Validate(InputType, OutputType)]` to each externally triggered workflow.
   - Keep workflow and node identifiers stable.
4. Make execution explicit:
   - Use sequential steps unless independence justifies `parallel`.
   - Use local, version-controlled scripts and function plugins for deterministic transformations.
   - Declare shell runtime, container packages, copied files, models, schemas, loop bounds, and service behavior.
   - Pass variable data through input or environment; never bake secrets or machine-specific paths into the bundle.
5. Add a `test` block for the public behavior. Prefer local functions and `COGNICORE_MOCK_LLM=1` for checks that would otherwise call a model. Do not claim reproducibility for live model, network, clock, or mutable remote behavior.
6. Run the bundled checker:

   ```bash
   .agents/skills/ocawe-write-pipelines/scripts/check_pipeline.sh PATH_TO_BUNDLE
   ```

7. Run the narrowest relevant repository specs, then the broader checks required by `AGENTS.md`. If runtime behavior is involved, start Ocawe with mock dependencies and run `ocawe test PATH_TO_BUNDLE`.
8. Report the exact commands and results. Call out any dependency that remains intentionally mutable or external.

## Starting a new bundle

Copy [assets/starter-pipeline](assets/starter-pipeline) into the requested location, rename its types and workflow ID, then replace the example function with real deterministic steps. Preserve its contract-first layout and local test pattern.

## Review gate

Do not finish until all applicable statements are true:

- Inputs and outputs are typed and validated.
- Every executable, plugin, agent, skill, and tool file is inside the bundle or explicitly packaged.
- Runtime dependencies are declared; versions are pinned where Ocawe supports pinning.
- No secret, host-specific absolute path, unbounded loop, floating image tag, or unpinned remote workflow is hidden in the definition.
- Parallel branches do not depend on each other's state or write colliding keys.
- Tests run without production credentials or uncontrolled network calls.
- The final handoff distinguishes verified behavior from environment-dependent behavior.
