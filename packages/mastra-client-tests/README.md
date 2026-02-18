# mastra-client-tests

Integration test suite for `@mastra/client-js` using `bun test` and an in-process compatibility test service with test workflows.

## Install

```bash
cd packages/mastra-client-tests
BUN_INSTALL=/tmp/bun-install BUN_TMPDIR=/tmp/bun-tmp bun install
```

## Run

```bash
bun test
bun test --coverage
```

## Coverage target

The suite validates all public client resources and methods (core, agents, tools, workflows, vectors, memory, logs, traces, evals) with success and failure paths.
