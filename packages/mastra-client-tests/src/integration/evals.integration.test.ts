import { fixtures } from "../test-utils/fixtures";
import { defineResourceMethodTests } from "../test-utils/suite";

defineResourceMethodTests("evals", [
  { method: "list", argSets: [[], [{ limit: 10 }]], pathHint: "/evals" },
  { method: "get", argSets: [[fixtures.evalId]], pathHint: "/evals" },
]);
