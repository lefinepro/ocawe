export type WorkflowMeta = {
  workflow_id: string;
  source_root_type: string;
  workflow_file: string;
  agents: string[];
  skills: string[];
  default_model?: string | null;
};

export type SkillMeta = {
  id: string;
  workflow_id: string;
  name: string;
  description: string;
};

export type ChatMessage = {
  role: "system" | "user" | "assistant";
  content: string;
};

export type AgentMeta = {
  id: string;
  name: string;
  workflow_id: string;
  description: string;
  model?: string | null;
  default_model?: string | null;
};

export type AgentDetail = AgentMeta & {
  prompt: string;
};

const API = "/api";

async function get<T>(path: string): Promise<T> {
  const r = await fetch(`${API}${path}`);
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json() as Promise<T>;
}

async function post<T>(path: string, body: unknown): Promise<T> {
  const r = await fetch(`${API}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body)
  });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json() as Promise<T>;
}

export async function listWorkflows(): Promise<string[]> {
  return get<string[]>("/v1/workflows");
}

export async function getWorkflow(id: string): Promise<WorkflowMeta> {
  return get<WorkflowMeta>(`/v1/workflows/${encodeURIComponent(id)}`);
}

export async function runWorkflow(id: string, input_data: Record<string, unknown>) {
  return post(`/v1/workflows/${encodeURIComponent(id)}/runs`, { input_data });
}

export async function listSkills(): Promise<{ skills: SkillMeta[] }> {
  return get<{ skills: SkillMeta[] }>("/v1/skills");
}

export async function executeSkill(skillId: string, payload: Record<string, unknown>) {
  return post(`/v1/skills/${encodeURIComponent(skillId)}/execute`, payload);
}

export async function listTools(): Promise<{ tools: Array<{ id: string; workflow_id: string }> }> {
  return get<{ tools: Array<{ id: string; workflow_id: string }> }>("/v1/tools");
}

export async function listAgents(): Promise<{ agents: AgentMeta[] }> {
  return get<{ agents: AgentMeta[] }>("/v1/agents");
}

export async function getAgent(id: string): Promise<AgentDetail> {
  return get<AgentDetail>(`/v1/agents/${encodeURIComponent(id)}`);
}

export async function generateAgent(
  agentId: string,
  payload: {
    messages: ChatMessage[];
    model?: string;
    system?: string;
    metadata?: Record<string, unknown>;
  }
): Promise<{ agent_id: string; workflow_id: string; provider: string; model: string; text: string }> {
  return post<{ agent_id: string; workflow_id: string; provider: string; model: string; text: string }>(
    `/v1/agents/${encodeURIComponent(agentId)}/generate`,
    payload
  );
}
