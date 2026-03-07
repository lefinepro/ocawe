<script lang="ts">
  import { onMount } from "svelte";
  import { listTools } from "../lib/api";

  let tools: Array<{ id: string; workflow_id: string }> = [];

  onMount(async () => {
    const data = await listTools();
    tools = data.tools;
  });
</script>

<div class="card">
  <h2>Tools</h2>
  <p class="muted">Tools discovered from loaded workflows.</p>
  <table class="table">
    <thead><tr><th>Tool</th><th>Workflow</th></tr></thead>
    <tbody>
      {#each tools as tool}
        <tr><td>{tool.id}</td><td>{tool.workflow_id}</td></tr>
      {/each}
    </tbody>
  </table>
</div>
