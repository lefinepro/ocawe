import { defineConfig } from "vitepress";

export default defineConfig({
  title: "Cogni",
  description: "Crystal-first runtime for workflows, agents, triggers, and skills",
  themeConfig: {
    nav: [
      { text: "Quickstart", link: "/guides/quickstart" },
      { text: "Guides", link: "/guides/core-concepts" },
      { text: "API", link: "/api/reference" },
    ],
    sidebar: [
      {
        text: "Overview",
        items: [
          { text: "Overview", link: "/" },
          { text: "Quickstart", link: "/guides/quickstart" },
          { text: "Core Concepts", link: "/guides/core-concepts" },
        ],
      },
      {
        text: "Guides",
        items: [
          { text: "Workflow Format", link: "/guides/workflow-format" },
          { text: "Registry And Extensions", link: "/guides/registry" },
          { text: "Examples", link: "/guides/examples" },
          { text: "Playground Route", link: "/guides/playground" },
          { text: "Directory Conventions", link: "/guides/directory-conventions" },
          { text: "Voice Workflow", link: "/guides/voice" },
          { text: "RAG Workflow", link: "/guides/rag" },
          { text: "Limits And Notes", link: "/guides/limits" },
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
      {
        text: "Ops Guides",
        items: [
          { text: "Maddy SMTP for Printers", link: "/guides/maddy-printers-smtp" },
          { text: "Maddy Users Bulk Create", link: "/guides/maddy-users-bulk-create" },
          { text: "Maddy Users Provisioning", link: "/guides/maddy-users-provisioning" },
          { text: "Maddy Deliverability", link: "/guides/maddy-deliverability" },
          { text: "Maddy Autodiscover", link: "/guides/maddy-autodiscover" },
          { text: "Maddy Outbound IP", link: "/guides/maddy-outbound-ip" },
          { text: "Maddy Webmail", link: "/guides/maddy-webmail" },
          { text: "Maddy Admin Lockdown", link: "/guides/maddy-admin-lockdown" },
          { text: "Maddy Fail2Ban", link: "/guides/maddy-fail2ban" },
          { text: "ISPmanager Add Domains", link: "/guides/ispmanager-add-domains" },
          { text: "ISPmanager Panel Domain", link: "/guides/ispmanager-panel-domain" },
        ],
      },
    ],
    search: {
      provider: "local",
    },
  },
});
