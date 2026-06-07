<script lang="ts">
  import { onMount } from "svelte";
  import { getWorkflow, listWorkflows, runWorkflow, type WorkflowMeta } from "../lib/api";
  import WorkflowGraph from "../components/WorkflowGraph.svelte";

  let workflows: string[] = [];
  let selected = "";
  let detail: WorkflowMeta | null = null;
  let runResult = "";

  async function load() {
    workflows = await listWorkflows();
    if (!selected && workflows.length > 0) {
      selected = workflows[0];
      detail = await getWorkflow(selected);
    }
  }

  async function selectWorkflow(id: string) {
    selected = id;
    detail = await getWorkflow(id);
  }

  async function startRun() {
    const result = await runWorkflow(selected, { task: "Playground test run" });
    runResult = JSON.stringify(result, null, 2);
  }

  onMount(load);
</script>

<div class="card">
  <h2>Workflows</h2>
  <p class="muted">Run workflows from OcaweCore.</p>
  <table class="table">
    <tbody>
      {#each workflows as id}
        <tr>
          <td>{id}</td>
          <td><button class="btn" on:click={() => selectWorkflow(id)}>Open</button></td>
        </tr>
      {/each}
    </tbody>
  </table>
</div>

{#if detail}
  <div class="card">
    <h3>{detail.workflow_id}</h3>
    <p class="muted">{detail.workflow_file}</p>
    <p><strong>Skills:</strong> {detail.skills.join(", ") || "none"}</p>
    <button class="btn primary" on:click={startRun}>Start Run</button>
    {#if runResult}
      <pre>{runResult}</pre>
    {/if}
  </div>
  <WorkflowGraph workflowId={detail.workflow_id} />
{/if}
