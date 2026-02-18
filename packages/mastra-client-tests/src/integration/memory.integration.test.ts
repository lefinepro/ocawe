import { fixtures } from "../test-utils/fixtures";
import { defineResourceMethodTests } from "../test-utils/suite";

defineResourceMethodTests("memory", [
  { method: "getStatus", argSets: [[fixtures.threadId], [{ threadId: fixtures.threadId }]], pathHint: "/memory" },
  {
    method: "updateStatus",
    argSets: [[fixtures.threadId, { enabled: true }], [{ threadId: fixtures.threadId, enabled: true }]],
    pathHint: "/memory",
  },
  { method: "getMessages", argSets: [[fixtures.threadId], [{ threadId: fixtures.threadId }]], pathHint: "/memory" },
  { method: "getWorkingMemory", argSets: [[fixtures.threadId], [{ threadId: fixtures.threadId }]], pathHint: "/memory" },
  {
    method: "generateMemory",
    argSets: [[fixtures.threadId, { messages: [{ role: "user", content: "remember this" }] }], [{ threadId: fixtures.threadId, messages: [{ role: "user", content: "remember this" }] }]],
    pathHint: "/memory",
  },
]);
