import { defineConfig } from "vitepress";

export default defineConfig({
  title: "Cogni",
  description: "Crystal-first runtime for workflows, agents, tools, and skills",
  themeConfig: {
    nav: [
      { text: "Guides", link: "/guides/tutorial" },
      { text: "Playground", link: "/playground/" },
      { text: "API", link: "/api/reference" },
    ],
    sidebar: [
      {
        text: "Start",
        items: [
          { text: "Overview", link: "/" },
          { text: "Tutorial", link: "/guides/tutorial" },
          { text: "Examples", link: "/guides/examples" },
        ],
      },
      {
        text: "Guides",
        items: [
          { text: "Playground Route", link: "/guides/playground" },
          { text: "Workflow Format", link: "/guides/workflow-format" },
          { text: "Directory Conventions", link: "/guides/directory-conventions" },
          { text: "Voice Workflow", link: "/guides/voice" },
          { text: "RAG Workflow", link: "/guides/rag" },
        ],
      },
      {
        text: "Playground",
        items: [
          { text: "Open Playground", link: "/playground/" },
        ],
      },
      {
        text: "API",
        items: [
          { text: "Reference", link: "/api/reference" },
        ],
      },
    ],
    search: {
      provider: "local",
    },
  },
});
