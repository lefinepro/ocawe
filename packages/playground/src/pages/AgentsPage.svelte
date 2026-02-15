<script lang="ts">
  import { onMount } from "svelte";
  import { generateAgent, getAgent, listAgents, type AgentDetail, type AgentMeta, type ChatMessage } from "../lib/api";

  let agents: AgentMeta[] = [];
  let selectedId = "";
  let selected: AgentDetail | null = null;
  let loading = false;
  let sending = false;
  let input = "";
  let modelOverride = "";
  let error = "";
  let messages: ChatMessage[] = [];

  async function load() {
    loading = true;
    error = "";
    try {
      const data = await listAgents();
      agents = data.agents;
      if (!selectedId && agents.length > 0) {
        await selectAgent(agents[0].id);
      }
    } catch (err) {
      error = err instanceof Error ? err.message : "Failed to load agents";
    } finally {
      loading = false;
    }
  }

  async function selectAgent(id: string) {
    selectedId = id;
    error = "";
    try {
      selected = await getAgent(id);
      messages = [];
    } catch (err) {
      error = err instanceof Error ? err.message : "Failed to load agent";
    }
  }

  async function sendMessage() {
    if (!selected || !input.trim() || sending) return;
    sending = true;
    error = "";

    const userMessage: ChatMessage = { role: "user", content: input.trim() };
    messages = [...messages, userMessage];
    input = "";

    try {
      const response = await generateAgent(selected.id, {
        messages,
        ...(modelOverride.trim() ? { model: modelOverride.trim() } : {}),
      });
      messages = [...messages, { role: "assistant", content: response.text }];
    } catch (err) {
      error = err instanceof Error ? err.message : "Failed to generate response";
    } finally {
      sending = false;
    }
  }

  function handleAgentSelect(event: Event) {
    const target = event.currentTarget as HTMLSelectElement | null;
    if (!target) return;
    void selectAgent(target.value);
  }

  onMount(load);
</script>

<div class="card">
  <h2>Agents</h2>
  <p class="muted">Mastra-style agent chat backed by `/v1/agents/:agentId/generate`.</p>

  {#if loading}
    <p class="muted">Loading agents...</p>
  {:else if !agents.length}
    <p class="muted">No agents discovered. Add markdown agents under a workflow bundle.</p>
  {:else}
    <label class="muted" for="agent-select">Agent</label>
    <select id="agent-select" class="input" bind:value={selectedId} on:change={handleAgentSelect}>
      {#each agents as agent}
        <option value={agent.id}>{agent.name} ({agent.workflow_id})</option>
      {/each}
    </select>
  {/if}
</div>

{#if selected}
  <div class="card">
    <h3>{selected.name}</h3>
    <p class="muted">{selected.description}</p>
    <p><strong>Workflow:</strong> {selected.workflow_id}</p>
    <p><strong>Model:</strong> {selected.model || selected.default_model || "openapi/qwen3-coder-plus"}</p>
    <label class="muted" for="model-override">Model override</label>
    <input id="model-override" class="input" bind:value={modelOverride} placeholder="openai/gpt-4.1-mini" />
  </div>

  <div class="card">
    <h3>Chat</h3>
    <div class="chat-log">
      {#if !messages.length}
        <p class="muted">No messages yet.</p>
      {:else}
        {#each messages as message}
          <div class="chat-message">
            <strong>{message.role}:</strong>
            <div>{message.content}</div>
          </div>
        {/each}
      {/if}
    </div>
    <textarea class="input" rows="4" bind:value={input} placeholder="Send a message to the selected agent"></textarea>
    <button class="btn primary" on:click={sendMessage} disabled={sending || !input.trim()}>
      {sending ? "Sending..." : "Send"}
    </button>
    {#if error}
      <p class="error">{error}</p>
    {/if}
  </div>
{/if}
