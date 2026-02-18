import { fixtures } from "../test-utils/fixtures";
import { defineResourceMethodTests } from "../test-utils/suite";

defineResourceMethodTests("workflows", [
  { method: "list", argSets: [[], [{ limit: 10 }]], pathHint: "/workflows" },
  { method: "create", argSets: [[{ name: "wf-new" }]], pathHint: "/workflows" },
  { method: "get", argSets: [[fixtures.workflowId]], pathHint: "/workflows" },
  {
    method: "run",
    argSets: [[fixtures.workflowId, { input: { text: "go" } }], [{ workflowId: fixtures.workflowId, input: { text: "go" } }]],
    pathHint: "/workflows",
  },
  {
    method: "resume",
    argSets: [[fixtures.workflowId, fixtures.runId, { input: {} }], [{ workflowId: fixtures.workflowId, runId: fixtures.runId, input: {} }]],
    pathHint: "/workflows",
  },
  {
    method: "watch",
    argSets: [[fixtures.workflowId, fixtures.runId], [{ workflowId: fixtures.workflowId, runId: fixtures.runId }]],
    pathHint: "/workflows",
  },
  { method: "getRuns", argSets: [[fixtures.workflowId], [{ workflowId: fixtures.workflowId }]], pathHint: "/workflows" },
  {
    method: "getRunResult",
    argSets: [[fixtures.workflowId, fixtures.runId], [{ workflowId: fixtures.workflowId, runId: fixtures.runId }]],
    pathHint: "/workflows",
  },
  {
    method: "cancelRun",
    argSets: [[fixtures.workflowId, fixtures.runId], [{ workflowId: fixtures.workflowId, runId: fixtures.runId }]],
    pathHint: "/workflows",
  },
  { method: "listSteps", argSets: [[fixtures.workflowId, fixtures.runId], [{ workflowId: fixtures.workflowId, runId: fixtures.runId }]], pathHint: "/workflows" },
  {
    method: "getStepResult",
    argSets: [
      [fixtures.workflowId, fixtures.runId, "step-1"],
      [{ workflowId: fixtures.workflowId, runId: fixtures.runId, stepId: "step-1" }],
    ],
    pathHint: "/workflows",
  },
]);
