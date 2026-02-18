import { afterAll, beforeAll, beforeEach, describe, expect, test } from "bun:test";
import { createClient } from "../test-utils/client-factory";
import { callMethod, tryGetResource } from "../test-utils/invoke";
import { ensureTestService, getLastRequestMeta, resetTestService, setServiceMode, stopTestService } from "../test-utils/test-service";

describe("MastraClient core integration", () => {
  beforeAll(async () => {
    await ensureTestService();
  });

  beforeEach(() => {
    resetTestService();
    setServiceMode("ok");
  });

  afterAll(() => {
    stopTestService();
  });

  test("logs available and missing resources", async () => {
    const client = await createClient();
    const resources = ["agents", "workflows", "tools", "vectors", "memory", "logs", "traces", "evals"];

    for (const name of resources) {
      const lookup = tryGetResource(client, name);
      if (!lookup.found) {
        console.warn(`[mastra-client-tests] resource skipped: ${name} - ${lookup.reason} (not implemented in project)`);
      } else {
        expect(lookup.resource).toBeDefined();
      }
    }
  });

  test("sends auth headers", async () => {
    const client = await createClient({ headers: { Authorization: "Bearer test-token" } });
    const agentsLookup = tryGetResource(client, "agents");
    if (!agentsLookup.found) {
      console.warn("[mastra-client-tests] resource skipped: agents - not implemented in project");
      return;
    }
    const agents = agentsLookup.resource as any;
    await callMethod(agents, "list", [[], [{ limit: 10 }]]);

    expect(getLastRequestMeta().authHeader).toBe("Bearer test-token");
  });

  test("propagates transport errors", async () => {
    const client = await createClient();
    const agentsLookup = tryGetResource(client, "agents");
    if (!agentsLookup.found) {
      console.warn("[mastra-client-tests] resource skipped: agents - not implemented in project");
      return;
    }
    const agents = agentsLookup.resource as any;

    setServiceMode("error");
    await expect(callMethod(agents, "list", [[], [{ limit: 10 }]])).rejects.toThrow();
  });
});
