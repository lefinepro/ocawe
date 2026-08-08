{ pkgs, pipelinesRoot ? ../../../sireng/pipelines, ... }:

let
  runtime = import ./ocawe-runtime.nix { inherit pkgs; };
  crawlerScript = pkgs.writeText "seacher-crawl.mjs" ''
    import { chromium } from "${pkgs.playwright-driver}/index.mjs";

    const targetUrl = process.argv[2];
    const timeout = Number(process.env.SEACHER_CRAWL_TIMEOUT_MS || "6000");
    if (!targetUrl || !/^https?:\/\//i.test(targetUrl)) {
      console.error("usage: crawl.mjs https://example.com/");
      process.exit(2);
    }

    let browser;
    try {
      browser = await chromium.launch({
        headless: true,
        args: ["--no-sandbox", "--disable-dev-shm-usage"],
      });
      const page = await browser.newPage({
        userAgent: "orator-seacher-crawler/1.0",
        viewport: { width: 1365, height: 768 },
      });
      await page.goto(targetUrl, { waitUntil: "domcontentloaded", timeout });
      await page.waitForLoadState("networkidle", { timeout: Math.min(timeout, 2500) }).catch(() => {});
      const data = await page.evaluate(() => {
        const links = Array.from(document.querySelectorAll("a[href]"))
          .slice(0, 60)
          .map((anchor) => ({
            text: (anchor.textContent || "").replace(/\s+/g, " ").trim(),
            href: anchor.href,
          }))
          .filter((link) => link.href);
        return {
          url: document.querySelector("link[rel='canonical']")?.href || location.href,
          title: document.title || "",
          text: document.body?.innerText || "",
          links,
        };
      });
      console.log(JSON.stringify(data));
    } finally {
      if (browser) await browser.close();
    }
  '';
in
{
  name = "seacher";
  target = "/opt/seacher";
  compose = "/opt/seacher/docker-compose.yml";
  project = "seacher";
  requiresExistingCompose = false;
  afterCompose = [
    "fmatch"
    "orator"
  ];
  extraCompose = "";
  healthCheck = "nerdctl ps --filter name=seacher --format '{{.Status}}' | awk '$0 == \"Up\" { ok = 1 } END { exit ok ? 0 : 1 }'";
  healthRetries = 90;
  healthInterval = 2;
  preCompose = ''
    ${runtime.skipIfRunning "seacher"}
    ${runtime.ensureSource "seacher runtime"}

    ${runtime.reuseOrBuildImage { image = "seacher"; }}

    mkdir -p /opt/seacher/workflows/seacher/seacher /opt/seacher/ocawe-state /opt/seacher/data /opt/seacher/tools
    cp -p ${pipelinesRoot}/seacher/Cawfile /opt/seacher/workflows/seacher/Cawfile
    awk 'BEGIN { emit = 1 } /^settings do/ { emit = 0 } emit { print }' \
      /opt/seacher/workflows/seacher/Cawfile > /opt/seacher/workflows/seacher/seacher/registry.cr
    printf '\nOcawe::RegistryApi.node_kind("seacher_handle_activity") do |ctx, _attributes|\n  Seacher.handle(Seacher.activity_from(ctx))\nend\n' >> /opt/seacher/workflows/seacher/seacher/registry.cr
    cp /opt/seacher/workflows/seacher/seacher/registry.cr /opt/seacher/workflows/seacher/registry.cr
    sed -i '2irequire "seacher/registry"' /opt/seacher/workflows/seacher/Cawfile
    awk 'index($0, "@[Container") != 1 { print }' /opt/seacher/workflows/seacher/Cawfile > /opt/seacher/workflows/seacher/Cawfile.runtime
    mv /opt/seacher/workflows/seacher/Cawfile.runtime /opt/seacher/workflows/seacher/Cawfile
    cp -p ${crawlerScript} /opt/seacher/tools/crawl.mjs
    chmod +x /opt/seacher/tools/crawl.mjs
    container_ip() {
      container_id="$(nerdctl ps -a 2>/dev/null | awk -v name="$1" '$NF == name { print $1; exit }')"
      if [ -z "$container_id" ]; then
        return 1
      fi
      nerdctl inspect "$container_id" 2>/dev/null | ${pkgs.jq}/bin/jq -r '.[0].NetworkSettings.Networks[]?.IPAddress // empty' | awk '/^10[.]4[.]1[.]/{ print; exit }'
    }
    if fmatch_ip="$(container_ip fmatch)" && [ -n "$fmatch_ip" ]; then
      export FMATCH_HTTP_HOST="$fmatch_ip"
    fi
    if orator_ip="$(container_ip orator)" && [ -n "$orator_ip" ]; then
      export ORATOR_HTTP_HOST="$orator_ip"
    fi
    if orator_app_ip="$(container_ip orator-app)" && [ -n "$orator_app_ip" ]; then
      export ORATOR_APP_HTTP_HOST="$orator_app_ip"
    fi
    if planner_ip="$(container_ip planner)" && [ -n "$planner_ip" ]; then
      export PLANNER_HTTP_HOST="$planner_ip"
    fi
    typesense_id="$(nerdctl ps -a 2>/dev/null | awk -v name="typesense" '$NF == name { print $1; exit }')"
    typesense_ip=""
    if [ -n "$typesense_id" ]; then
      typesense_ip="$(nerdctl inspect "$typesense_id" 2>/dev/null | ${pkgs.jq}/bin/jq -r '.[0].NetworkSettings.Networks[]?.IPAddress // empty' | head -n1)"
    fi
    if [ -n "$typesense_ip" ]; then
      export TYPESENSE_HTTP_HOST="$typesense_ip"
    fi
    if [ -f /opt/fmatch/.env ]; then
      export SEACHER_TYPESENSE_API_KEY="$(awk -F= '/^TYPESENSE_API_KEY=/ { print $2; exit }' /opt/fmatch/.env)"
    fi
    cat > /opt/seacher/docker-compose.yml <<'YAML'
    services:
      seacher:
        image: seacher:latest
        container_name: seacher
        entrypoint: ["${pkgs.bash}/bin/bash", "-c"]
        command:
          - |
            export PATH="${pkgs.crystal}/bin:${pkgs.shards}/bin:${pkgs.pkg-config}/bin:${pkgs.gcc}/bin:${pkgs.coreutils}/bin:${pkgs.curl}/bin:${pkgs.nodejs_22}/bin:/usr/bin:/bin:/app/tools:/tools:''${PATH:-}";
            export PKG_CONFIG_PATH="${pkgs.sqlite.dev}/lib/pkgconfig:${pkgs.boehmgc.dev}/lib/pkgconfig:${pkgs.openssl.dev}/lib/pkgconfig:${pkgs.libyaml.dev}/lib/pkgconfig:${pkgs.pcre2.dev}/lib/pkgconfig:${pkgs.zlib.dev}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}";
            export LIBRARY_PATH="${pkgs.sqlite.out}/lib:${pkgs.boehmgc}/lib:${pkgs.openssl.out}/lib:${pkgs.libyaml}/lib:${pkgs.pcre2}/lib:${pkgs.zlib}/lib:${pkgs.gmp}/lib:''${LIBRARY_PATH:-}";
            export CPATH="${pkgs.sqlite.dev}/include:${pkgs.boehmgc.dev}/include:${pkgs.openssl.dev}/include:${pkgs.libyaml.dev}/include:${pkgs.pcre2.dev}/include:${pkgs.zlib.dev}/include:${pkgs.gmp.dev}/include:''${CPATH:-}";
            mkdir -p /tmp /bin;
            ln -sfn ${pkgs.bash}/bin/bash /bin/sh;
            printf 'require "ocawe"\nrequire "registry"\nOcaweCore.run\n' > /tmp/seacher_runtime_entry.cr;
            CRYSTAL_PATH=/ocawe/src:/ocawe/lib:/workflows/seacher:$(crystal env CRYSTAL_PATH) crystal build /tmp/seacher_runtime_entry.cr -o /tmp/seachercore && exec /tmp/seachercore --port 8080
        restart: unless-stopped
        environment:
          PORT: "8080"
          SEACHER_ACTOR_ID: "http://seacher:8080/actors/seacher"
          SEACHER_CURL_BIN: "${pkgs.curl}/bin/curl"
          SEACHER_CRAWLER_BIN: "${pkgs.nodejs_22}/bin/node"
          SEACHER_CRAWLER_SCRIPT: "/tools/crawl.mjs"
          SEACHER_CRAWL_TIMEOUT_MS: "6000"
          SEACHER_DB_PATH: "/data/seacher.sqlite3"
          SEACHER_MODEL_CATALOG_URL: "http://''${ORATOR_APP_HTTP_HOST:-orator-app}:8080/v1/models"
          SEACHER_POPULAR_THRESHOLD: "2"
          SEACHER_INSTANCE_URLS: "fmatch=http://''${FMATCH_HTTP_HOST:-fmatch}:7277/actor/orator,orator=http://''${ORATOR_HTTP_HOST:-orator}:8080/actors/orator,planner=http://''${PLANNER_HTTP_HOST:-planner}:8080/actors/planner"
          SEACHER_TYPESENSE_URL: "http://''${TYPESENSE_HTTP_HOST:-typesense}:8108"
          SEACHER_TYPESENSE_API_KEY: "''${SEACHER_TYPESENSE_API_KEY:-}"
          SEACHER_TYPESENSE_COLLECTION: "seacher_sites"
          OCAWE_RESULTS_DIR: "/results"
          OCAWE_FEDERATION_SIGNATURES_REQUIRED: "false"
          OCAWE_FEDERATION_ACTOR_NAME: "seacher"
          OCAWE_FEDERATION_ACTOR_SUMMARY: "DuckDuckGo search and Playwright crawl workflow"
          OCAWE_FEDERATION_TAGS: "search,crawl,crawler,duckduckgo,playwright"
          OCAWE_FEDERATION_RESOURCE_CONFORMS_TO: "https://fmatch/marketplace/resources/seacher"
          OCAWE_FEDERATION_ACTION: "deliverService"
          OCAWE_FEDERATION_PURPOSE: "request"
          OCAWE_WORKFLOWS_ROOT: "/workflows/seacher"
          SSL_CERT_FILE: "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          NIX_SSL_CERT_FILE: "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          PLAYWRIGHT_BROWSERS_PATH: "${pkgs.playwright-driver.browsers}"
          PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS: "true"
          PATH: "${pkgs.crystal}/bin:${pkgs.shards}/bin:${pkgs.pkg-config}/bin:${pkgs.gcc}/bin:${pkgs.coreutils}/bin:${pkgs.curl}/bin:${pkgs.nodejs_22}/bin:/usr/bin:/bin:/app/tools:/tools"
        ports:
          - "127.0.0.1:8084:8080"
        volumes:
          - /opt/orator/results:/results
          - /opt/seacher/data:/data
          - /opt/seacher/tools:/tools:ro
          - /root/deployments/sireng/reps/ocawe:/ocawe:ro
          - /nix/store:/nix/store:ro
          - ./workflows:/workflows
        networks:
          lefine-net:
            aliases:
              - seacher

networks:
  lefine-net:
    external: true
    name: lefine-net
YAML
    awk 'BEGIN { top_networks = 0 } /^networks:/ { top_networks = 1 } { if (!top_networks) sub(/^    /, ""); print }' \
      /opt/seacher/docker-compose.yml > /opt/seacher/docker-compose.yml.normalized
    mv /opt/seacher/docker-compose.yml.normalized /opt/seacher/docker-compose.yml
    if [ -n "''${TYPESENSE_HTTP_HOST:-}" ]; then
      sed -i "s#SEACHER_TYPESENSE_URL: .*#SEACHER_TYPESENSE_URL: \"http://$TYPESENSE_HTTP_HOST:8108\"#" /opt/seacher/docker-compose.yml
    fi
    if [ -n "''${SEACHER_TYPESENSE_API_KEY:-}" ]; then
      sed -i "s#SEACHER_TYPESENSE_API_KEY: .*#SEACHER_TYPESENSE_API_KEY: \"$SEACHER_TYPESENSE_API_KEY\"#" /opt/seacher/docker-compose.yml
    fi
  '';
  postCompose = "";
}
