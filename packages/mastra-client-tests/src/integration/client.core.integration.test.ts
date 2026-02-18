import { describe, expect, test } from "bun:test";
import { http, HttpResponse } from "msw";
import { createClient } from "../test-utils/client-factory";
import { callMethod, getResource, tryGetResource } from "../test-utils/invoke";
import { server, useMswLifecycle } from "../test-utils/msw-server";

describe("MastraClient core integration", () => {
  useMswLifecycle();

  test("creates required resource accessors and logs optional drift", () => {
    const client = createClient();
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
    let authHeader = "";
    server.use(
      http.all(/http:\/\/mastra\.local\/.*/, ({ request }) => {
        authHeader = request.headers.get("authorization") ?? "";
        return HttpResponse.json({ ok: true });
      }),
    );

    const client = createClient({ headers: { Authorization: "Bearer test-token" } });
    const agents = getResource(client, "agents");
    await callMethod(agents, "list", [[], [{ limit: 10 }]]);

    expect(authHeader).toBe("Bearer test-token");
  });

  test("propagates transport errors", async () => {
    server.use(http.all(/http:\/\/mastra\.local\/.*/, () => HttpResponse.error()));

    const client = createClient();
    const agents = getResource(client, "agents");

    await expect(callMethod(agents, "list", [[], [{ limit: 10 }]])).rejects.toThrow();
  });
});
