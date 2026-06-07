<script lang="ts">
  import WorkflowsPage from "./pages/WorkflowsPage.svelte";
  import ToolsPage from "./pages/ToolsPage.svelte";
  import SkillsPage from "./pages/SkillsPage.svelte";
  import AgentsPage from "./pages/AgentsPage.svelte";
  import SimpleTextPage from "./pages/SimpleTextPage.svelte";
  import { navCategories } from "./lib/categories";

  let route = window.location.hash.replace(/^#\/?/, "") || "agents";
  window.addEventListener("hashchange", () => {
    route = window.location.hash.replace(/^#\/?/, "") || "agents";
  });

</script>

<div class="app-shell">
  <aside class="sidebar">
    <div class="brand">Ocawe Playground</div>
    {#each navCategories as nav}
      <a class="nav-item {route === nav.id ? 'active' : ''}" href={`#/${nav.id}`}>{nav.label}</a>
    {/each}
  </aside>

  <main class="content">
    {#if route === "agents"}
      <AgentsPage />
    {:else if route === "workflows"}
      <WorkflowsPage />
    {:else if route === "tools"}
      <ToolsPage />
    {:else if route === "skills"}
      <SkillsPage />
    {:else if route === "voice"}
      <SimpleTextPage title="Voice" body="Use workflow id voice-playground and Crystal voice tools." />
    {:else if route === "rag"}
      <SimpleTextPage title="RAG" body="Use workflow id rag-playground and Crystal RAG tools." />
    {:else if route === "settings"}
      <SimpleTextPage title="Settings" body="Dev proxy uses /api -> OcaweCore server configured in vite proxy." />
    {:else}
      <SimpleTextPage title="Not found" body="Unknown route" />
    {/if}
  </main>
</div>
