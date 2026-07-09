# mastra-client-tests

Integration test suite for `@mastra/client-js` using Vitest on Node.js and an
in-process compatibility test service with test workflows.

## Install

```bash
cd packages/mastra-client-tests
pnpm install
```

## Run

```bash
pnpm run test
pnpm run test:integration:coverage
```

## Coverage target

The suite validates all public client resources and methods (core, agents,
tools, workflows, vectors, memory, logs, traces, evals) with success and
failure paths.
