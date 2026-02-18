import { fixtures } from "../test-utils/fixtures";
import { defineResourceMethodTests } from "../test-utils/suite";

defineResourceMethodTests("vectors", [
  { method: "list", argSets: [[], [{ limit: 10 }]], pathHint: "/vectors" },
  { method: "create", argSets: [[{ id: fixtures.vectorCollectionId, dimension: 1536 }]], pathHint: "/vectors" },
  { method: "get", argSets: [[fixtures.vectorCollectionId]], pathHint: "/vectors" },
  { method: "delete", argSets: [[fixtures.vectorCollectionId]], pathHint: "/vectors" },
]);
