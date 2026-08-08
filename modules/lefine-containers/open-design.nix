{ ... }:

{
  name = "open-design";
  target = "/opt/open-design";
  compose = "/opt/open-design/docker-compose.yml";
  project = "open-design";
  requiresExistingCompose = false;
  afterCompose = [ "source-forgejo" ];
  extraCompose = "";
  preCompose = ''
    mkdir -p /opt/open-design

    api_token_file="/opt/open-design/.api-token"
    if [ ! -s "$api_token_file" ]; then
      openssl rand -hex 32 > "$api_token_file"
      chmod 600 "$api_token_file"
    fi
    api_token="$(cat "$api_token_file")"

    if [ ! -s /opt/open-design/designer-password ]; then
      openssl rand -base64 24 > /opt/open-design/designer-password
      chmod 600 /opt/open-design/designer-password
    fi

    if [ ! -s /opt/open-design/caddy.env ]; then
      password="$(cat /opt/open-design/designer-password)"
      hash="$(nerdctl run --rm caddy:2.8-alpine caddy hash-password --plaintext "$password")"
      {
        printf 'OD_API_TOKEN=%s\n' "$api_token"
        printf 'OPEN_DESIGN_BASIC_AUTH_HASH=%s\n' "$hash"
      } > /opt/open-design/caddy.env
      chmod 600 /opt/open-design/caddy.env
    elif ! grep -q '^OD_API_TOKEN=' /opt/open-design/caddy.env; then
      printf 'OD_API_TOKEN=%s\n' "$api_token" >> /opt/open-design/caddy.env
    fi

    source_dir="/opt/open-design/source"
    if [ ! -d "$source_dir/.git" ]; then
      rm -rf "$source_dir"
      git clone --depth 1 https://github.com/nexu-io/open-design.git "$source_dir"
    else
      git -C "$source_dir" fetch --depth 1 origin main
      git -C "$source_dir" checkout --detach FETCH_HEAD
    fi

    source_rev="$(git -C "$source_dir" rev-parse HEAD)"
    built_rev_file="/opt/open-design/.built-rev"
    if ! nerdctl image inspect open-design-local:latest >/dev/null 2>&1 \
      || [ ! -s "$built_rev_file" ] \
      || [ "$(cat "$built_rev_file")" != "$source_rev" ]; then
      nerdctl build -t open-design-local:latest -f "$source_dir/deploy/Dockerfile" "$source_dir"
      printf '%s\n' "$source_rev" > "$built_rev_file"
    fi

    codex_built_rev_file="/opt/open-design/.codex-built-rev"
    if ! nerdctl image inspect open-design-codex:latest >/dev/null 2>&1 \
      || [ ! -s "$codex_built_rev_file" ] \
      || [ "$(cat "$codex_built_rev_file")" != "$source_rev" ]; then
      nerdctl rm -f od-codex-build >/dev/null 2>&1 || true
      nerdctl run --name od-codex-build --user root --entrypoint sh open-design-local:latest \
        -lc "npm install -g @openai/codex && codex --version"
      nerdctl commit od-codex-build open-design-codex:latest
      nerdctl rm -f od-codex-build >/dev/null 2>&1 || true
      printf '%s\n' "$source_rev" > "$codex_built_rev_file"
    fi

    cat > /opt/open-design/.env <<EOF
    OPEN_DESIGN_IMAGE=open-design-codex:latest
    OPEN_DESIGN_ALLOWED_ORIGINS=https://lefine.pro
    OPEN_DESIGN_PORT=7456
    OPEN_DESIGN_MEM_LIMIT=384m
    NODE_OPTIONS=--max-old-space-size=192
    OD_API_TOKEN=$api_token
    OD_CODEX_SANDBOX=danger-full-access
    CODEX_HOME=/app/.od/codex
    EOF
    chmod 600 /opt/open-design/.env

    cat > /opt/open-design/docker-compose.yml <<'YAML'
    services:
      open-design:
        image: ''${OPEN_DESIGN_IMAGE:-ghcr.io/nexu-io/od:latest}
        container_name: open-design
        restart: unless-stopped
        environment:
          NODE_ENV: production
          NODE_OPTIONS: ''${NODE_OPTIONS:---max-old-space-size=192}
          OD_BIND_HOST: 0.0.0.0
          OD_ALLOWED_ORIGINS: ''${OPEN_DESIGN_ALLOWED_ORIGINS:-}
          OD_PORT: 7456
          OD_WEB_PORT: ''${OPEN_DESIGN_PORT:-7456}
          OD_API_TOKEN: ''${OD_API_TOKEN:-}
          OD_CODEX_SANDBOX: ''${OD_CODEX_SANDBOX:-}
          CODEX_HOME: ''${CODEX_HOME:-/app/.od/codex}
        expose:
          - "7456"
        volumes:
          - open_design_data:/app/.od
        read_only: true
        tmpfs:
          - /tmp
        security_opt:
          - no-new-privileges:true
        mem_limit: ''${OPEN_DESIGN_MEM_LIMIT:-384m}
        pids_limit: 256
        healthcheck:
          test:
            [
              "CMD",
              "node",
              "-e",
              "fetch('http://127.0.0.1:7456/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
            ]
          interval: 30s
          timeout: 5s
          retries: 3
          start_period: 20s
        networks:
          - lefine-net

    volumes:
      open_design_data:

    networks:
      lefine-net:
        external: true
        name: lefine-net
    YAML
  '';
  postCompose = ''
    nerdctl exec --user root open-design sh -lc \
      'mkdir -p /app/.od/codex && chown -R open-design:open-design /app/.od/codex'
  '';
}
