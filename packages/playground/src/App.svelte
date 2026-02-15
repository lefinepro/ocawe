<script lang="ts">
  import WorkflowsPage from "./pages/WorkflowsPage.svelte";
  import ToolsPage from "./pages/ToolsPage.svelte";
  import SkillsPage from "./pages/SkillsPage.svelte";
  import SimpleTextPage from "./pages/SimpleTextPage.svelte";
  import UnsupportedPage from "./pages/UnsupportedPage.svelte";
  import { allCategories, getCategory, navCategories } from "./lib/categories";

  let route = window.location.hash.replace(/^#\/?/, "") || "workflows";
  window.addEventListener("hashchange", () => {
    route = window.location.hash.replace(/^#\/?/, "") || "workflows";
  });

  $: category = getCategory(route);
</script>

<div class="app-shell">
  <aside class="sidebar">
    <div class="brand">Cogni Playground</div>
    {#each navCategories as nav}
      <a class="nav-item {route === nav.id ? 'active' : ''}" href={`#/${nav.id}`}>{nav.label}</a>
    {/each}
    <hr style="margin: 14px 0; border: none; border-top: 1px solid var(--line);" />
    <div class="muted" style="font-size: 12px;">Hidden categories kept in code: {allCategories.filter(c => !c.showInNav).map(c => c.id).join(", ")}</div>
  </aside>

  <main class="content">
    {#if route === "workflows"}
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
      <SimpleTextPage title="Settings" body="Dev proxy uses /api -> CogniCore server configured in vite proxy." />
    {:else if category}
      <UnsupportedPage category={category.label} reason={category.reason || "Not supported in CogniCore framework"} />
    {:else}
      <SimpleTextPage title="Not found" body="Unknown route" />
    {/if}
  </main>
</div>
