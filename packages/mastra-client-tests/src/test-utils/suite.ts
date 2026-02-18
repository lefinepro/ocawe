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

function isNotImplementedError(error: unknown): boolean {
  const message = error instanceof Error ? error.message.toLowerCase() : String(error).toLowerCase();
  return (
    message.includes("not implemented") ||
    message.includes("not supported") ||
    message.includes("unsupported") ||
    message.includes("status 404") ||
    message.includes("404") ||
    message.includes("status 501") ||
    message.includes("501")
  );
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
  describe(`${resourceName} integration`, () => {
    useServiceLifecycle();

    for (const scenario of scenarios) {
      test(`${scenario.method}: success`, async () => {
        const client = await createClient();
        const lookup = tryGetResource(client, resourceName);
        if (!lookup.found) {
          warnOptionalSkip(resourceName, scenario.method, `${lookup.reason} (not implemented in project)`);
          return;
        }

        if (!hasMethod(lookup.resource, scenario.method)) {
          const reason = `Method '${scenario.method}' is not available`;
          warnOptionalSkip(resourceName, scenario.method, `${reason} (not implemented in project)`);
          return;
        }

        const verifier = makeRequestVerifier();
        let result: unknown;
        try {
          result = await callMethod(lookup.resource, scenario.method, scenario.argSets);
        } catch (error) {
          if (isNotImplementedError(error)) {
            warnOptionalSkip(resourceName, scenario.method, "backend method is not implemented");
            return;
          }
          throw error;
        }

        verifier.captureFromMeta(getLastRequestMeta());
        expect(result).not.toBeUndefined();
        expect(verifier.lastMethod()).not.toBe("");
        if (scenario.pathHint) {
          expect(verifier.lastPath()).toContain(scenario.pathHint);
        }
      });

      test(`${scenario.method}: failure`, async () => {
        const client = await createClient();
        const lookup = tryGetResource(client, resourceName);
        if (!lookup.found) {
          warnOptionalSkip(resourceName, scenario.method, `${lookup.reason} (not implemented in project)`);
          return;
        }

        if (!hasMethod(lookup.resource, scenario.method)) {
          const reason = `Method '${scenario.method}' is not available`;
          warnOptionalSkip(resourceName, scenario.method, `${reason} (not implemented in project)`);
          return;
        }

        setServiceMode("error");
        const error = await expectMethodFailure(lookup.resource, scenario.method, scenario.argSets);
        if (isNotImplementedError(error)) {
          warnOptionalSkip(resourceName, scenario.method, "backend method is not implemented");
          return;
        }

        expect(error.message.length).toBeGreaterThan(0);
      });
    }
  });
}
