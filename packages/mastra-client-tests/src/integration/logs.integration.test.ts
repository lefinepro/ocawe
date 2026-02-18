import { fixtures } from "../test-utils/fixtures";
import { defineResourceMethodTests } from "../test-utils/suite";

defineResourceMethodTests("logs", [
  {
    method: "listByResource",
    argSets: [[fixtures.resourceId], [{ resourceId: fixtures.resourceId, limit: 10 }]],
    pathHint: "/logs",
  },
  {
    method: "listBySession",
    argSets: [[fixtures.threadId], [{ sessionId: fixtures.threadId, limit: 10 }]],
    pathHint: "/logs",
  },
]);
