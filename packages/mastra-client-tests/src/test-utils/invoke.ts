function asError(value: unknown): Error {
  return value instanceof Error ? value : new Error(String(value));
}

export type ResourceLookupResult =
  | { found: true; resource: unknown }
  | { found: false; reason: string };

function parseAgentCall(args: unknown[]): { agentId: string; payload: any } {
  if (typeof args[0] === "string") {
    return { agentId: args[0], payload: args[1] ?? {} };
  }

  const payload = (args[0] as any) ?? {};
  return { agentId: payload.agentId ?? payload.id ?? "agent-weather", payload };
}

function createAgentsAdapter(client: any): any {
  if (typeof client?.listAgents !== "function" || typeof client?.getAgent !== "function") {
    return null;
  }

  return {
    async list(...args: any[]) {
      return client.listAgents(...args);
    },
    async get(id: string) {
      const agent = client.getAgent(id);
      if (agent?.details) return agent.details();
      return agent;
    },
    async generate(...args: any[]) {
      const { agentId, payload } = parseAgentCall(args);
      const agent = client.getAgent(agentId);
      const input = payload?.messages ?? payload?.prompt ?? payload?.input ?? payload ?? "hello";
      const opts = typeof payload === "object" ? payload : undefined;
      return agent.generate(input, opts);
    },
    async streamGenerate(...args: any[]) {
      const { agentId, payload } = parseAgentCall(args);
      const agent = client.getAgent(agentId);
      const input = payload?.messages ?? payload?.prompt ?? payload?.input ?? payload ?? "hello";
      const opts = typeof payload === "object" ? payload : undefined;
      return agent.stream(input, opts);
    },
    async stream(...args: any[]) {
      const { agentId, payload } = parseAgentCall(args);
      const agent = client.getAgent(agentId);
      const input = payload?.messages ?? payload?.prompt ?? payload?.input ?? payload ?? "hello";
      const opts = typeof payload === "object" ? payload : undefined;
      return agent.stream(input, opts);
    },
    async getInstructions(id: string) {
      const agent = client.getAgent(id);
      const details = agent?.details ? await agent.details() : agent;
      return details?.instructions ?? details;
    },
  };
}

function createWorkflowsAdapter(client: any): any {
  if (typeof client?.listWorkflows !== "function" || typeof client?.getWorkflow !== "function") {
    return null;
  }

  return {
    async list(...args: any[]) {
      return client.listWorkflows(...args);
    },
    async get(id: string) {
      const workflow = client.getWorkflow(id);
      if (workflow?.details) return workflow.details();
      return workflow;
    },
    async run(...args: any[]) {
      const workflowId = typeof args[0] === "string" ? args[0] : args[0]?.workflowId;
      const payload = typeof args[0] === "string" ? args[1] ?? {} : args[0] ?? {};
      const workflow = client.getWorkflow(workflowId);
      if (workflow?.run) return workflow.run(payload);
      if (workflow?.start) return workflow.start(payload);
      throw new Error("Method 'run' is not available");
    },
    async watch(...args: any[]) {
      const workflowId = typeof args[0] === "string" ? args[0] : args[0]?.workflowId;
      const workflow = client.getWorkflow(workflowId);
      if (workflow?.watch) return workflow.watch(args[1] ?? args[0]);
      throw new Error("Method 'watch' is not available");
    },
  };
}

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

  if (name === "agents") {
    const adapter = createAgentsAdapter(client);
    if (adapter) {
      return { found: true, resource: adapter };
    }
  }

  if (name === "workflows") {
    const adapter = createWorkflowsAdapter(client);
    if (adapter) {
      return { found: true, resource: adapter };
    }
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
