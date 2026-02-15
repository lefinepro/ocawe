import { defineConfig } from "vitepress";

export default defineConfig({
  title: "Cogni Docs",
  description: "CogniCore API and text guides",
  themeConfig: {
    nav: [
      { text: "Guides", link: "/guides/playground" },
      { text: "API", link: "/api/reference" }
    ],
    sidebar: [
      {
        text: "Guides",
        items: [
          { text: "Playground", link: "/guides/playground" },
          { text: "Workflow Format", link: "/guides/workflow-format" },
          { text: "Directory Conventions", link: "/guides/directory-conventions" },
          { text: "Examples", link: "/guides/examples" },
          { text: "Voice Workflow", link: "/guides/voice" },
          { text: "RAG Workflow", link: "/guides/rag" },
          { text: "Tutorial", link: "/guides/tutorial" }
        ]
      },
      {
        text: "API",
        items: [
          { text: "Reference", link: "/api/reference" }
        ]
      }
    ]
  }
});
