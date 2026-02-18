function asError(value: unknown): Error {
  return value instanceof Error ? value : new Error(String(value));
}

export function getResource(client: any, name: string): any {
  const direct = client?.[name];
  if (direct) {
    return typeof direct === "function" ? direct.call(client) : direct;
  }

  const getter = client?.[`get${name[0].toUpperCase()}${name.slice(1)}`];
  if (typeof getter === "function") {
    return getter.call(client);
  }

  throw new Error(`Resource '${name}' is not available on MastraClient`);
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
    lastPath: () => path,
    lastMethod: () => method,
  };
}
