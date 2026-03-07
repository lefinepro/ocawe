import { fixtures } from "../test-utils/fixtures";
import { defineResourceMethodTests } from "../test-utils/suite";

defineResourceMethodTests("traces", [
  {
    method: "listByResource",
    argSets: [[fixtures.resourceId], [{ resourceId: fixtures.resourceId, limit: 10 }]],
    pathHint: "/traces",
  },
  {
    method: "listBySession",
    argSets: [[fixtures.threadId], [{ sessionId: fixtures.threadId, limit: 10 }]],
    pathHint: "/traces",
  },
]);
