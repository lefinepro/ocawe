# Cogni

Crystal-first runtime for workflows, agents, triggers, and skills.

Licenses: [ISC](https://spdx.org/licenses/ISC.html) (`LICENSE`) and [0BSD](https://spdx.org/licenses/0BSD.html) (`LICENSE-0BSD`).

## What You Can Build

- Agent-driven workflows with explicit graph execution.
- Function/script and skill orchestration from workflow bundles.
- Voice and RAG workflows with typed schema validation.
- Local playground-driven development with runtime APIs.

## Quickstart

```bash
crystal build src/cli/main.cr -o build/cogni
./build/cogni up --port 4111
```

Start the Svelte playground:

```bash
cd packages/playground
bun install
bun run dev
```

Open docs and playground route:

- Docs: `http://localhost:5173/`
- Playground route: `http://localhost:5173/playground/`

## Next Steps

- Tutorial: `/guides/tutorial`
- Workflow format: `/guides/workflow-format`
- Registry API: `/guides/registry`
- Maddy SMTP for printers: `/guides/maddy-printers-smtp`
- Maddy users bulk create: `/guides/maddy-users-bulk-create`
- Maddy Deliverability (SPF/DKIM/DMARC): `/guides/maddy-deliverability`
- Maddy Autodiscover/Autoconfig: `/guides/maddy-autodiscover`
- Maddy Outbound Multi-IP (domain -> IP): `/guides/maddy-outbound-ip`
- Webmail for Maddy (Roundcube + ISPmanager): `/guides/maddy-webmail`
- Fail2Ban for Maddy: `/guides/maddy-fail2ban`
- Admin Lockdown (Maddy + ISPmanager): `/guides/maddy-admin-lockdown`
- ISPmanager: add 5 domains: `/guides/ispmanager-add-domains`
- API reference: `/api/reference`
- Workflow API spec: `/api/workflow-api-spec`
- Trigger API spec: `/api/trigger-api-spec`
