<script lang="ts">
  import { SvelteFlow, Background } from "@xyflow/svelte";
  import "@xyflow/svelte/dist/style.css";

  export let workflowId: string;

  const nodes = [
    { id: "start", position: { x: 0, y: 60 }, data: { label: "workflow" }, type: "input" },
    { id: "agent", position: { x: 240, y: 60 }, data: { label: "agent/skill/tool" } },
    { id: "end", position: { x: 500, y: 60 }, data: { label: "result" }, type: "output" }
  ];

  const edges = [
    { id: "e1", source: "start", target: "agent", animated: true },
    { id: "e2", source: "agent", target: "end" }
  ];
</script>

<div class="card">
  <h3>Workflow Graph</h3>
  <p class="muted">SvelteFlow view for {workflowId}</p>
  <div style="height: 320px; border: 1px solid var(--line); border-radius: 10px; overflow: hidden;">
    <SvelteFlow {nodes} {edges} fitView>
      <Background />
    </SvelteFlow>
  </div>
</div>
