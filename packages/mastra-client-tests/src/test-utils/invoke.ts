function asError(value: unknown): Error {
  return value instanceof Error ? value : new Error(String(value));
}

export type ResourceLookupResult =
  | { found: true; resource: unknown }
  | { found: false; reason: string };

export function tryGetResource(client: any, name: string): ResourceLookupResult {
  const direct = client?.[name];
  if (direct) {
    return { found: true, resource: typeof direct === "function" ? direct.call(client) : direct };
  }

  const getterName = `get${name[0].toUpperCase()}${name.slice(1)}`;
  const getter = client?.[getterName];
  if (typeof getter === "function") {
    return { found: true, resource: getter.call(client) };
  }

  return {
    found: false,
    reason: `Resource '${name}' is not available on MastraClient`,
  };
}

export function getResource(client: any, name: string): any {
  const lookup = tryGetResource(client, name);
  if (lookup.found) {
    return lookup.resource;
  }

  throw new Error(lookup.reason);
}

export function hasMethod(target: any, method: string): boolean {
  return typeof target?.[method] === "function";
}

export async function callMethod(target: any, method: string, argSets: unknown[][]): Promise<any> {
  const fn = target?.[method];
  if (typeof fn !== "function") {
    throw new Error(`Method '${method}' is not available`);
  }

  let lastError: Error | undefined;
  for (const args of argSets) {
    try {
      return await fn.apply(target, args);
    } catch (error) {
      lastError = asError(error);
    }
  }

  throw lastError ?? new Error(`Method '${method}' failed for all argument variants`);
}

export async function expectMethodFailure(target: any, method: string, argSets: unknown[][]): Promise<Error> {
  try {
    await callMethod(target, method, argSets);
  } catch (error) {
    return asError(error);
  }

  throw new Error(`Expected '${method}' to fail, but it resolved successfully`);
}

export function makeRequestVerifier(): {
  capture: (request: Request) => Promise<void>;
  captureFromMeta: (meta: { method: string; path: string }) => void;
  lastPath: () => string;
  lastMethod: () => string;
} {
  let method = "";
  let path = "";

  return {
    capture: async (request: Request) => {
      method = request.method;
      path = new URL(request.url).pathname;
      await request.text();
    },
    captureFromMeta: (meta: { method: string; path: string }) => {
      method = meta.method;
      path = meta.path;
    },
    lastPath: () => path,
    lastMethod: () => method,
  };
}
