import { defineConfig } from "vitepress";

export default defineConfig({
  title: "Ocawe",
  description: "Crystal-first runtime for workflows, agents, triggers, and skills",
  themeConfig: {
    nav: [
      { text: "Docs", link: "/guides/quickstart" },
      { text: "Guides", link: "/guides/concepts" },
      { text: "Playground", link: "/playground/" },
      { text: "API", link: "/api/reference" },
    ],
    sidebar: [
      {
        text: "Getting Started",
        items: [
          { text: "Overview", link: "/" },
          { text: "Quickstart", link: "/guides/quickstart" },
          { text: "Tutorial", link: "/guides/tutorial" },
          { text: "Examples", link: "/guides/examples" },
        ],
      },
      {
        text: "Core Concepts",
        items: [
          { text: "Concepts", link: "/guides/concepts" },
          { text: "Agents", link: "/guides/agents" },
          { text: "Workflows", link: "/guides/workflows" },
          { text: "Tools", link: "/guides/tools" },
        ],
      },
      {
        text: "Features",
        items: [
          { text: "Voice Workflow", link: "/guides/voice" },
          { text: "RAG Workflow", link: "/guides/rag" },
          { text: "Playground", link: "/guides/playground" },
        ],
      },
      {
        text: "Advanced",
        items: [
          { text: "Workflow Format", link: "/guides/workflow-format" },
          { text: "Registry API", link: "/guides/registry" },
          { text: "Directory Conventions", link: "/guides/directory-conventions" },
        ],
      },
      {
        text: "API Reference",
        items: [
          { text: "API Overview", link: "/api/reference" },
          { text: "Workflow API", link: "/api/workflow-api-spec" },
          { text: "Trigger API", link: "/api/trigger-api-spec" },
        ],
      },
      {
        text: "Changelog",
        items: [
          { text: "Changelog", link: "/changelog" },
        ],
      },
    ],
    search: {
      provider: "local",
    },
  },
});
