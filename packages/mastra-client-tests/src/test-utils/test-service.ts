const encoder = new TextEncoder();

type Mode = "ok" | "error";

type RequestMeta = {
  method: string;
  path: string;
  authHeader: string;
};

type RunRecord = {
  id: string;
  workflowId: string;
  status: "running" | "completed";
  createdAt: string;
};

type ServiceState = {
  mode: Mode;
  lastRequest: RequestMeta;
  runs: Map<string, RunRecord>;
  runCounter: number;
};

const state: ServiceState = {
  mode: "ok",
  lastRequest: { method: "", path: "", authHeader: "" },
  runs: new Map(),
  runCounter: 0,
};

const AGENT = { id: "agent-weather", name: "Weather Agent" };
const WORKFLOW = { id: "workflow-onboarding", name: "Onboarding" };

let server: ReturnType<typeof Bun.serve> | null = null;

function json(data: unknown, init?: ResponseInit): Response {
  return Response.json(data, init);
}

function nextRunId(): string {
  state.runCounter += 1;
  return `run-${String(state.runCounter).padStart(3, "0")}`;
}

function sseResponse(): Response {
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(
        encoder.encode('data: {"type":"text-delta","payload":{"text":"ok"}}\n\n'),
      );
      controller.enqueue(
        encoder.encode('data: {"type":"finish","payload":{"finishReason":"stop"}}\n\n'),
      );
      controller.close();
    },
  });

  return new Response(stream, {
    status: 200,
    headers: {
      "content-type": "text/event-stream",
      "cache-control": "no-cache",
      connection: "keep-alive",
    },
  });
}

function shouldStream(req: Request): boolean {
  const accept = req.headers.get("accept") ?? "";
  if (accept.includes("text/event-stream")) return true;
  return false;
}

async function handleAgents(req: Request, pathname: string): Promise<Response> {
  if (pathname.endsWith("/agents") && req.method === "GET") {
    return json({ agents: [AGENT] });
  }

  if (req.method === "GET") {
    return json({ ...AGENT, path: pathname });
  }

  if (req.method === "POST") {
    if (shouldStream(req) || pathname.includes("stream")) {
      return sseResponse();
    }
    return json({ agentId: AGENT.id, output: "ok" });
  }

  if (req.method === "DELETE") {
    return new Response(null, { status: 204 });
  }

  return json({ ok: true, path: pathname });
}

async function handleWorkflows(req: Request, pathname: string): Promise<Response> {
  if (pathname.endsWith("/workflows") && req.method === "GET") {
    return json({ workflows: [WORKFLOW] });
  }

  if (pathname.endsWith("/workflows") && req.method === "POST") {
    return json({ ...WORKFLOW });
  }

  if (pathname.includes("/watch") || shouldStream(req)) {
    return sseResponse();
  }

  if (pathname.includes("/run") || pathname.includes("/resume") || pathname.endsWith("/runs")) {
    const runId = nextRunId();
    const record: RunRecord = {
      id: runId,
      workflowId: WORKFLOW.id,
      status: "completed",
      createdAt: new Date().toISOString(),
    };
    state.runs.set(runId, record);
    return json({ runId, status: "completed" });
  }

  if (pathname.includes("/runs") && req.method === "GET") {
    return json({ runs: Array.from(state.runs.values()) });
  }

  if (req.method === "GET") {
    return json({ ...WORKFLOW, path: pathname });
  }

  if (req.method === "DELETE") {
    return new Response(null, { status: 204 });
  }

  return json({ ok: true, path: pathname });
}

async function handleCompat(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const pathname = url.pathname;

  state.lastRequest = {
    method: req.method,
    path: pathname,
    authHeader: req.headers.get("authorization") ?? "",
  };

  if (state.mode === "error") {
    return json({ error: "forced failure" }, { status: 500 });
  }

  if (pathname.includes("/agents")) {
    return handleAgents(req, pathname);
  }

  if (pathname.includes("/workflows")) {
    return handleWorkflows(req, pathname);
  }

  if (pathname.includes("/tools")) {
    return json({ tools: [{ id: "tool-summarize" }], ok: true, path: pathname });
  }

  if (pathname.includes("/vectors")) {
    return json({ vectors: [{ id: "vectors-main" }], ok: true, path: pathname });
  }

  if (pathname.includes("/memory")) {
    return json({ threadId: "thread-001", ok: true, path: pathname });
  }

  if (pathname.includes("/logs")) {
    return json({ logs: [{ id: "log-001" }], ok: true, path: pathname });
  }

  if (pathname.includes("/traces")) {
    return json({ traces: [{ id: "trace-001" }], ok: true, path: pathname });
  }

  if (pathname.includes("/evals")) {
    return json({ evals: [{ id: "eval-001" }], ok: true, path: pathname });
  }

  return json({ ok: true, path: pathname });
}

function resetState(): void {
  state.mode = "ok";
  state.lastRequest = { method: "", path: "", authHeader: "" };
  state.runs.clear();
  state.runCounter = 0;
}

export async function ensureTestService(): Promise<string> {
  if (server) {
    return `http://127.0.0.1:${server.port}`;
  }

  resetState();
  server = Bun.serve({
    port: 0,
    fetch: handleCompat,
  });

  return `http://127.0.0.1:${server.port}`;
}

export function stopTestService(): void {
  if (!server) return;
  server.stop(true);
  server = null;
}

export function resetTestService(): void {
  resetState();
}

export function setServiceMode(mode: Mode): void {
  state.mode = mode;
}

export function getLastRequestMeta(): RequestMeta {
  return { ...state.lastRequest };
}
