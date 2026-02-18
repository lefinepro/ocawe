import { afterAll, beforeAll, beforeEach, describe, expect, test } from "bun:test";
import { createClient } from "../test-utils/client-factory";
import { callMethod, getResource, tryGetResource } from "../test-utils/invoke";
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

  test("creates required resource accessors and logs optional drift", async () => {
    const client = await createClient();
    const requiredResources = ["agents", "workflows"];
    const optionalResources = ["tools", "vectors", "memory", "logs", "traces", "evals"];

    for (const name of requiredResources) {
      const resource = getResource(client, name);
      expect(resource).toBeDefined();
    }

    for (const name of optionalResources) {
      const lookup = tryGetResource(client, name);
      if (!lookup.found) {
        console.warn(`[mastra-client-tests] optional resource missing: ${name} - ${lookup.reason}`);
      }
    }
  });

  test("sends auth headers", async () => {
    const client = await createClient({ headers: { Authorization: "Bearer test-token" } });
    const agents = getResource(client, "agents");
    await callMethod(agents, "list", [[], [{ limit: 10 }]]);

    expect(getLastRequestMeta().authHeader).toBe("Bearer test-token");
  });

  test("propagates transport errors", async () => {
    const client = await createClient();
    const agents = getResource(client, "agents");

    setServiceMode("error");
    await expect(callMethod(agents, "list", [[], [{ limit: 10 }]])).rejects.toThrow();
  });
});
