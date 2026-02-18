import { fixtures } from "../test-utils/fixtures";
import { defineResourceMethodTests } from "../test-utils/suite";

defineResourceMethodTests("agents", [
  { method: "list", argSets: [[], [{ limit: 10 }]], pathHint: "/agents", required: true },
  { method: "get", argSets: [[fixtures.agentId]], pathHint: "/agents", required: true },
  {
    method: "generate",
    argSets: [
      [fixtures.agentId, { messages: [{ role: "user", content: "hello" }] }],
      [{ agentId: fixtures.agentId, messages: [{ role: "user", content: "hello" }] }],
    ],
    pathHint: "/agents",
    required: true,
  },
  {
    method: "stream",
    argSets: [
      [fixtures.agentId, { messages: [{ role: "user", content: "stream" }] }],
      [{ agentId: fixtures.agentId, messages: [{ role: "user", content: "stream" }] }],
    ],
    pathHint: "/agents",
    required: true,
  },
  {
    method: "streamGenerate",
    argSets: [
      [fixtures.agentId, { messages: [{ role: "user", content: "stream" }] }],
      [{ agentId: fixtures.agentId, messages: [{ role: "user", content: "stream" }] }],
    ],
    pathHint: "/agents",
  },
  { method: "getInstructions", argSets: [[fixtures.agentId]], pathHint: "/agents" },
  { method: "getOutput", argSets: [[fixtures.agentId]], pathHint: "/agents" },
  { method: "listOutputVersions", argSets: [[fixtures.agentId]], pathHint: "/agents" },
  { method: "getOutputVersion", argSets: [[fixtures.agentId, "v1"], [{ agentId: fixtures.agentId, version: "v1" }]], pathHint: "/agents" },
  {
    method: "updateOutputVersion",
    argSets: [[fixtures.agentId, "v1", { active: true }], [{ agentId: fixtures.agentId, version: "v1", active: true }]],
    pathHint: "/agents",
  },
  { method: "deleteOutputVersion", argSets: [[fixtures.agentId, "v1"], [{ agentId: fixtures.agentId, version: "v1" }]], pathHint: "/agents" },
  { method: "getMemory", argSets: [[fixtures.agentId, fixtures.threadId], [{ agentId: fixtures.agentId, threadId: fixtures.threadId }]], pathHint: "/agents" },
  { method: "getLiveTools", argSets: [[fixtures.agentId]], pathHint: "/agents" },
]);
