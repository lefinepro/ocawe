import { fixtures } from "../test-utils/fixtures";
import { defineResourceMethodTests } from "../test-utils/suite";

defineResourceMethodTests("tools", [
  { method: "list", argSets: [[], [{ limit: 10 }]], pathHint: "/tools" },
  { method: "get", argSets: [[fixtures.toolId]], pathHint: "/tools" },
  {
    method: "execute",
    argSets: [[fixtures.toolId, { input: { text: "hello" } }], [{ toolId: fixtures.toolId, input: { text: "hello" } }]],
    pathHint: "/tools",
  },
]);
