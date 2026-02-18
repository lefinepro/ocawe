export const fixtures = {
  agentId: "agent-weather",
  toolId: "tool-summarize",
  workflowId: "workflow-onboarding",
  runId: "run-001",
  threadId: "thread-001",
  resourceId: "resource-001",
  vectorCollectionId: "vectors-main",
  traceId: "trace-001",
  evalId: "eval-001",
};

export function ok<T>(data: T): T {
  return data;
}
