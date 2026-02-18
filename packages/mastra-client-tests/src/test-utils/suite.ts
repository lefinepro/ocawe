import { describe, expect, test } from "bun:test";
import { http, HttpResponse } from "msw";
import { createClient, TEST_BASE_URL } from "./client-factory";
import { callMethod, expectMethodFailure, getResource, makeRequestVerifier } from "./invoke";
import { server, useMswLifecycle } from "./msw-server";

export type ResourceScenario = {
  method: string;
  argSets: unknown[][];
  pathHint?: string;
  response?: Record<string, unknown>;
};

export function defineResourceMethodTests(resourceName: string, scenarios: ResourceScenario[]): void {
  describe(`${resourceName} integration`, () => {
    useMswLifecycle();

    for (const scenario of scenarios) {
      test(`${scenario.method}: success`, async () => {
        const verifier = makeRequestVerifier();
        server.use(
          http.all(/http:\/\/mastra\.local\/.*/, async ({ request }) => {
            await verifier.capture(request);
            return HttpResponse.json(
              scenario.response ?? { ok: true, resource: resourceName, method: scenario.method },
              { status: 200 },
            );
          }),
        );

        const client = createClient();
        const resource = getResource(client, resourceName);
        const result = await callMethod(resource, scenario.method, scenario.argSets);

        expect(result).not.toBeUndefined();
        expect(verifier.lastMethod()).not.toBe("");
        if (scenario.pathHint) {
          expect(verifier.lastPath()).toContain(scenario.pathHint);
        }
      });

      test(`${scenario.method}: failure`, async () => {
        server.use(
          http.all(/http:\/\/mastra\.local\/.*/, () =>
            HttpResponse.json({ error: "forced failure" }, { status: 500 }),
          ),
        );

        const client = createClient();
        const resource = getResource(client, resourceName);
        const error = await expectMethodFailure(resource, scenario.method, scenario.argSets);

        expect(error.message.length).toBeGreaterThan(0);
      });
    }
  });
}
