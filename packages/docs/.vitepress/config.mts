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
        text: "Deployment Guides",
        collapsed: true,
        items: [
          { text: "Maddy SMTP for Printers", link: "/guides/maddy-printers-smtp" },
          { text: "Maddy Users Bulk Create", link: "/guides/maddy-users-bulk-create" },
          { text: "Maddy Deliverability", link: "/guides/maddy-deliverability" },
          { text: "Maddy Autodiscover", link: "/guides/maddy-autodiscover" },
          { text: "Maddy Admin Lockdown", link: "/guides/maddy-admin-lockdown" },
          { text: "Maddy Fail2Ban", link: "/guides/maddy-fail2ban" },
          { text: "ISPmanager Panel Domain", link: "/guides/ispmanager-panel-domain" },
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
    ],
    search: {
      provider: "local",
    },
  },
});
