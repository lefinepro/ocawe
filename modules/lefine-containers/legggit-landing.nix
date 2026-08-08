{
  pkgs,
  containersCfg ? null,
  ...
}:

let
  cfg = if containersCfg == null then { } else (containersCfg.legggitLanding or { });
  sourceRepo = cfg.sourceRepo or "https://codeberg.org/kogeletey/legggit-landing.git";
  sourceBranch = cfg.sourceBranch or "main";
  siteUrl = cfg.siteUrl or "https://legggit.ru";
  smtpEnvFile = cfg.smtpEnvFile or "/opt/maddy-webmail/data/legggit-landing-smtp.env";
  target = "/opt/legggit-landing";
  image = "legggit-landing:latest";
  port = cfg.port or "3000";
  fallbackSmtpHost = cfg.fallbackSmtpHost or "mail.lefine.pro";
  fallbackSmtpUser = cfg.fallbackSmtpUser or "order@lefine.pro";
  fallbackLeadMailbox = cfg.fallbackLeadMailbox or "order@lefine.pro";
  buildConfigRevision = "pnpm-workspace-output-hybrid-leggent-domain-v4";
  compose = pkgs.writeText "legggit-landing-compose.yml" ''
    services:
      legggit-landing:
        image: ${image}
        container_name: legggit-landing
        restart: unless-stopped
        environment:
          NODE_ENV: production
          HOST: 0.0.0.0
          PORT: "${port}"
          SITE_URL: ${siteUrl}
          LEADS_DB_PATH: /var/lib/legggit-landing/leads.sqlite
          SMTP_HOST: "''${SMTP_HOST:-${fallbackSmtpHost}}"
          SMTP_PORT: "''${SMTP_PORT:-587}"
          SMTP_USER: "''${SMTP_USER:-${fallbackSmtpUser}}"
          SMTP_PASS: "''${SMTP_PASS:-}"
          LEAD_TO_EMAIL: "''${LEAD_TO_EMAIL:-${fallbackLeadMailbox}}"
          LEAD_FROM_EMAIL: "''${LEAD_FROM_EMAIL:-${fallbackLeadMailbox}}"
          SMTP_TLS_REJECT_UNAUTHORIZED: "false"
        user: "0"
        volumes:
          - /var/lib/legggit-landing:/var/lib/legggit-landing
        ports:
          - "127.0.0.1:${port}:${port}"
        networks:
          - lefine-net

    networks:
      lefine-net:
        external: true
        name: lefine-net
  '';
in
{
  name = "legggit-landing";
  target = target;
  compose = "${target}/docker-compose.yml";
  project = "legggit-landing";
  requiresExistingCompose = false;
  afterCompose = [ "maddy-webmail" ];
  extraCompose = "";
  healthCheck = "curl -fsS http://127.0.0.1:${port}/ >/dev/null";
  healthRetries = 30;
  healthInterval = 2;
  preCompose = ''
        set -euo pipefail

        target_dir="${target}"
        source_dir="$target_dir/source"
        source_rev_file="$target_dir/.source-rev"
        built_rev_file="$target_dir/.built-rev"
        repo_cache="/root/deployments/sireng/reps/legggit-landing"

        mkdir -p "$target_dir"
        mkdir -p /var/lib/legggit-landing

        if [ -d "$source_dir/.git" ]; then
          :
        elif [ -d "$repo_cache/.git" ]; then
          rm -rf "$source_dir"
          cp -a "$repo_cache" "$source_dir"
        else
          git clone --depth 1 --branch ${sourceBranch} ${sourceRepo} "$source_dir"
        fi

        if [ -d "$source_dir/.git" ]; then
          git -C "$source_dir" fetch --depth 1 origin ${sourceBranch}
          git -C "$source_dir" checkout ${sourceBranch}
          git -C "$source_dir" reset --hard "origin/${sourceBranch}" || true
        fi

        package_json="$source_dir/package.json"
        if [ -f "$package_json" ]; then
          tmp_package_json="$package_json.tmp"
          jq '.pnpm.onlyBuiltDependencies = ((.pnpm.onlyBuiltDependencies // []) + ["better-sqlite3", "esbuild", "sharp"] | unique)' \
            "$package_json" > "$tmp_package_json"
          mv "$tmp_package_json" "$package_json"
        fi

        dockerfile="$source_dir/Dockerfile"
        if [ -f "$source_dir/pnpm-workspace.yaml" ] && [ -f "$dockerfile" ]; then
          sed -i \
            's/COPY package.json pnpm-lock.yaml \.\//COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .\//g' \
            "$dockerfile"
        fi

        astro_config="$source_dir/astro.config.mjs"
        if [ -f "$astro_config" ] && ! grep -Eq '^[[:space:]]*output:' "$astro_config"; then
          sed -i \
            "s/export default defineConfig({/export default defineConfig({\\n  output: isStatic ? 'static' : 'hybrid',/" \
            "$astro_config"
        fi

        find "$source_dir" \
          -path "$source_dir/.git" -prune -o \
          -path "$source_dir/node_modules" -prune -o \
          -path "$source_dir/dist" -prune -o \
          -type f -print \
          | xargs -r grep -Il 'leggent\.example\|hello@leggent\.example' \
          | xargs -r sed -i \
              -e 's/hello@leggent\.example/order@leggent.ru/g' \
              -e 's/no-reply@leggent\.example/order@leggent.ru/g' \
              -e 's/leggent\.example/leggent.ru/g'

        lead_form="$source_dir/src/components/islands/LeadForm.svelte"
        if [ -f "$lead_form" ]; then
          ${pkgs.perl}/bin/perl -0pi -e 's|  async function dispatch\(payload: Record<string, string>\) \{.*?  \}\n\n  async function onSubmit|  async function dispatch(payload: Record<string, string>) {\n    const res = await fetch("/api/lead", {\n      method: "POST",\n      headers: { "content-type": "application/json" },\n      body: JSON.stringify({ ...payload, website: hp }),\n    });\n    if (!res.ok) throw new Error("lead:" + res.status);\n    const body = await res.json().catch(() => ({}));\n    if (!body.ok) throw new Error("lead:" + (body.error ?? "unknown"));\n  }\n\n  async function onSubmit|s' "$lead_form"
        fi

        source_rev="$(git -C "$source_dir" rev-parse HEAD || true)"
        if [ -z "$source_rev" ]; then
          source_rev="unknown"
        fi
        build_rev="$source_rev:${buildConfigRevision}"

        cp ${compose} "$target_dir/docker-compose.yml"

        if [ ! -f "$source_rev_file" ] || [ ! -s "$source_rev_file" ] || [ "$source_rev" != "$(cat "$source_rev_file" 2>/dev/null || true)" ] || [ ! -s "$built_rev_file" ] || [ "$build_rev" != "$(cat "$built_rev_file" 2>/dev/null || true)" ] || ! nerdctl image inspect ${image} >/dev/null 2>&1; then
          nerdctl build -t ${image} -f "$source_dir/Dockerfile" "$source_dir"
          printf '%s\n' "$build_rev" > "$built_rev_file"
          printf '%s\n' "$source_rev" > "$source_rev_file"
        fi

        if [ ! -f ${smtpEnvFile} ]; then
          cat > ${smtpEnvFile} <<EOF
    SMTP_HOST=${fallbackSmtpHost}
    SMTP_PORT=587
    SMTP_USER=${fallbackSmtpUser}
    SMTP_PASS=
    LEAD_TO_EMAIL=${fallbackLeadMailbox}
    LEAD_FROM_EMAIL=${fallbackLeadMailbox}
    EOF
          chmod 600 ${smtpEnvFile}
        fi

        set -a
        . ${smtpEnvFile}
        set +a
  '';
  postCompose = "";
}
