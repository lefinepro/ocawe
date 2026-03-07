import { defineConfig } from "vitepress";

export default defineConfig({
  title: "Cogni",
  description: "Crystal-first runtime for workflows, agents, triggers, and skills",
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
          { text: "Maddy SMTP for Printers", link: "/guides/maddy-printers-smtp" },
          { text: "Maddy Users Bulk Create", link: "/guides/maddy-users-bulk-create" },
          { text: "Maddy Deliverability", link: "/guides/maddy-deliverability" },
          { text: "Maddy Autodiscover", link: "/guides/maddy-autodiscover" },
          { text: "Maddy Admin Lockdown", link: "/guides/maddy-admin-lockdown" },
          { text: "Maddy Fail2Ban", link: "/guides/maddy-fail2ban" },
          { text: "ISPmanager Panel Domain", link: "/guides/ispmanager-panel-domain" },
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
          { text: "Workflow API Spec", link: "/api/workflow-api-spec" },
          { text: "Trigger API Spec", link: "/api/trigger-api-spec" },
        ],
      },
    ],
    search: {
      provider: "local",
    },
  },
});
