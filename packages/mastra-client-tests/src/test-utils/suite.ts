import { afterAll, beforeAll, beforeEach, describe, expect, test } from "bun:test";
import { createClient } from "./client-factory";
import { callMethod, expectMethodFailure, hasMethod, makeRequestVerifier, tryGetResource } from "./invoke";
import { ensureTestService, getLastRequestMeta, resetTestService, setServiceMode, stopTestService } from "./test-service";

export type ResourceScenario = {
  method: string;
  argSets: unknown[][];
  pathHint?: string;
  required?: boolean;
};

export type ResourceSuiteOptions = {
  resourceRequired?: boolean;
};

function warnOptionalSkip(resourceName: string, method: string | null, reason: string): void {
  const methodLabel = method ? `.${method}` : "";
  console.warn(`[mastra-client-tests] optional check skipped: ${resourceName}${methodLabel} - ${reason}`);
}

function useServiceLifecycle(): void {
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
}

export function defineResourceMethodTests(
  resourceName: string,
  scenarios: ResourceScenario[],
  options: ResourceSuiteOptions = {},
): void {
  const resourceRequired = options.resourceRequired ?? false;

  describe(`${resourceName} integration`, () => {
    useServiceLifecycle();

    for (const scenario of scenarios) {
      test(`${scenario.method}: success`, async () => {
        const scenarioRequired = scenario.required ?? resourceRequired;
        const client = await createClient();
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
        const result = await callMethod(lookup.resource, scenario.method, scenario.argSets);

        verifier.captureFromMeta(getLastRequestMeta());
        expect(result).not.toBeUndefined();
        expect(verifier.lastMethod()).not.toBe("");
        if (scenario.pathHint) {
          expect(verifier.lastPath()).toContain(scenario.pathHint);
        }
      });

      test(`${scenario.method}: failure`, async () => {
        const scenarioRequired = scenario.required ?? resourceRequired;
        const client = await createClient();
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

        setServiceMode("error");
        const error = await expectMethodFailure(lookup.resource, scenario.method, scenario.argSets);

        expect(error.message.length).toBeGreaterThan(0);
      });
    }
  });
}
