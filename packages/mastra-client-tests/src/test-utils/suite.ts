import { describe, expect, test } from "bun:test";
import { http, HttpResponse } from "msw";
import { createClient } from "./client-factory";
import { callMethod, expectMethodFailure, hasMethod, makeRequestVerifier, tryGetResource } from "./invoke";
import { server, useMswLifecycle } from "./msw-server";

export type ResourceScenario = {
  method: string;
  argSets: unknown[][];
  pathHint?: string;
  response?: Record<string, unknown>;
  required?: boolean;
};

export type ResourceSuiteOptions = {
  resourceRequired?: boolean;
};

function warnOptionalSkip(resourceName: string, method: string | null, reason: string): void {
  const methodLabel = method ? `.${method}` : "";
  // CI-friendly warning for optional API drift with @mastra/client-js@latest.
  console.warn(`[mastra-client-tests] optional check skipped: ${resourceName}${methodLabel} - ${reason}`);
}

export function defineResourceMethodTests(
  resourceName: string,
  scenarios: ResourceScenario[],
  options: ResourceSuiteOptions = {},
): void {
  const resourceRequired = options.resourceRequired ?? false;

  describe(`${resourceName} integration`, () => {
    useMswLifecycle();

    for (const scenario of scenarios) {
      test(`${scenario.method}: success`, async () => {
        const scenarioRequired = scenario.required ?? resourceRequired;
        const client = createClient();
        const lookup = tryGetResource(client, resourceName);
        if (!lookup.found) {
          if (scenarioRequired) {
            throw new Error(lookup.reason);
          }
          warnOptionalSkip(resourceName, scenario.method, lookup.reason);
          return;
        }

        if (!hasMethod(lookup.resource, scenario.method)) {
          const reason = `Method '${scenario.method}' is not available`;
          if (scenarioRequired) {
            throw new Error(reason);
          }
          warnOptionalSkip(resourceName, scenario.method, reason);
          return;
        }

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

        const result = await callMethod(lookup.resource, scenario.method, scenario.argSets);

        expect(result).not.toBeUndefined();
        expect(verifier.lastMethod()).not.toBe("");
        if (scenario.pathHint) {
          expect(verifier.lastPath()).toContain(scenario.pathHint);
        }
      });

      test(`${scenario.method}: failure`, async () => {
        const scenarioRequired = scenario.required ?? resourceRequired;
        const client = createClient();
        const lookup = tryGetResource(client, resourceName);
        if (!lookup.found) {
          if (scenarioRequired) {
            throw new Error(lookup.reason);
          }
          warnOptionalSkip(resourceName, scenario.method, lookup.reason);
          return;
        }

        if (!hasMethod(lookup.resource, scenario.method)) {
          const reason = `Method '${scenario.method}' is not available`;
          if (scenarioRequired) {
            throw new Error(reason);
          }
          warnOptionalSkip(resourceName, scenario.method, reason);
          return;
        }

        server.use(
          http.all(/http:\/\/mastra\.local\/.*/, () =>
            HttpResponse.json({ error: "forced failure" }, { status: 500 }),
          ),
        );

        const error = await expectMethodFailure(lookup.resource, scenario.method, scenario.argSets);

        expect(error.message.length).toBeGreaterThan(0);
      });
    }
  });
}
