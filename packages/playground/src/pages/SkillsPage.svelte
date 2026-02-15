<script lang="ts">
  import { onMount } from "svelte";
  import { executeSkill, listSkills, type SkillMeta } from "../lib/api";

  let skills: SkillMeta[] = [];
  let selected: SkillMeta | null = null;
  let output = "";

  onMount(async () => {
    const data = await listSkills();
    skills = data.skills;
    selected = skills[0] || null;
  });

  async function runSelected() {
    if (!selected) return;
    const result = await executeSkill(selected.id, { input: "Playground skill test" });
    output = JSON.stringify(result, null, 2);
  }
</script>

<div class="card">
  <h2>Skills</h2>
  <p class="muted">Skills are first-class, parallel to tools.</p>
  <table class="table">
    <thead><tr><th>Skill</th><th>Workflow</th><th></th></tr></thead>
    <tbody>
      {#each skills as skill}
        <tr>
          <td>{skill.id}</td><td>{skill.workflow_id}</td>
          <td><button class="btn" on:click={() => (selected = skill)}>Select</button></td>
        </tr>
      {/each}
    </tbody>
  </table>
</div>

{#if selected}
  <div class="card">
    <h3>{selected.name}</h3>
    <p class="muted">{selected.description}</p>
    <button class="btn primary" on:click={runSelected}>Execute Skill</button>
    {#if output}<pre>{output}</pre>{/if}
  </div>
{/if}
