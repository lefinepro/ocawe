{ pkgs, pipelinesRoot ? ../../../sireng/pipelines, ... }:

let
  runtime = import ./ocawe-runtime.nix { inherit pkgs; };
  oratorCaddyfile = pkgs.writeText "orator-Caddyfile" ''
    :8080 {
      @authorized header_regexp Authorization "^Bearer ({$API_KEYS_PATTERN})$"

      handle /health {
        reverse_proxy __ORATOR_APP_UPSTREAM__
      }

      handle /metrics {
        reverse_proxy __ORATOR_APP_UPSTREAM__
      }

      handle /.well-known/webfinger {
        reverse_proxy __ORATOR_APP_UPSTREAM__
      }

      handle /actors/* {
        reverse_proxy __ORATOR_APP_UPSTREAM__
      }

      handle /inbox {
        reverse_proxy __ORATOR_APP_UPSTREAM__
      }

      handle @authorized {
        handle /v1 {
          header Content-Type application/json
          respond "{\"object\":\"api\",\"status\":\"ok\",\"models\":\"/v1/models\",\"chat_completions\":\"/v1/chat/completions\"}" 200
        }

        handle /v1/ {
          header Content-Type application/json
          respond "{\"object\":\"api\",\"status\":\"ok\",\"models\":\"/v1/models\",\"chat_completions\":\"/v1/chat/completions\"}" 200
        }

        handle /v1/models {
          header Content-Type application/json
          respond "{\"object\":\"list\",\"data\":[{\"id\":\"acct:orator@lefine.pro\",\"object\":\"model\",\"created\":0,\"owned_by\":\"lefinepro\"}]}" 200
        }

        handle /models {
          header Content-Type application/json
          respond "{\"object\":\"list\",\"data\":[{\"id\":\"acct:orator@lefine.pro\",\"object\":\"model\",\"created\":0,\"owned_by\":\"lefinepro\"}]}" 200
        }

        reverse_proxy __ORATOR_APP_UPSTREAM__ {
          @created status 201
          replace_status @created 200
        }
      }

      handle {
        respond "Unauthorized" 401
      }
    }
  '';

  oratorCompose = pkgs.writeText "orator-compose.yml" ''
    services:
      orator-app:
        image: orator:latest
        container_name: orator-app
        entrypoint: ["${pkgs.bash}/bin/bash", "-c"]
        command:
          - |
            export PATH="${pkgs.crystal}/bin:${pkgs.shards}/bin:${pkgs.pkg-config}/bin:${pkgs.gcc}/bin:${pkgs.coreutils}/bin:${pkgs.zsh}/bin:${pkgs.curl}/bin:${pkgs.jq}/bin:${pkgs.openssl}/bin:/usr/bin:/bin:/app/tools:''${PATH:-}";
            export PKG_CONFIG_PATH="${pkgs.sqlite.dev}/lib/pkgconfig:${pkgs.boehmgc.dev}/lib/pkgconfig:${pkgs.openssl.dev}/lib/pkgconfig:${pkgs.libyaml.dev}/lib/pkgconfig:${pkgs.pcre2.dev}/lib/pkgconfig:${pkgs.zlib.dev}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}";
            export LIBRARY_PATH="${pkgs.sqlite.out}/lib:${pkgs.boehmgc}/lib:${pkgs.openssl.out}/lib:${pkgs.libyaml}/lib:${pkgs.pcre2}/lib:${pkgs.zlib}/lib:${pkgs.gmp}/lib:''${LIBRARY_PATH:-}";
            export CPATH="${pkgs.sqlite.dev}/include:${pkgs.boehmgc.dev}/include:${pkgs.openssl.dev}/include:${pkgs.libyaml.dev}/include:${pkgs.pcre2.dev}/include:${pkgs.zlib.dev}/include:${pkgs.gmp.dev}/include:''${CPATH:-}";
            mkdir -p /tmp /bin;
            ln -sfn ${pkgs.bash}/bin/bash /bin/sh;
            printf 'require "ocawe"\nOcaweCore.run\n' > /tmp/orator_runtime_entry.cr;
            CRYSTAL_PATH=/ocawe/src:/ocawe/lib:/workflows/orator:$(crystal env CRYSTAL_PATH) crystal build /tmp/orator_runtime_entry.cr -o /tmp/oratorcore && exec /tmp/oratorcore --port 8080
        restart: unless-stopped
        env_file:
          - /opt/orator/.env
        environment:
          ORATOR_CRADA_REPOSITORY_ID: "orator"
          ORATOR_CRADA_ORDER_ID: "default"
          ORATOR_STORAGE_ACTOR_URL: "https://lefine.pro/actors/orator"
          ORATOR_CRADA_STORAGE_URL: "http://crada:3001"
          FMATCH_ACTOR_ID: "https://lefine.pro/actors/orator"
          FMATCH_INBOX_URL: "https://lefine.pro/actors/orator/inbox"
          FMATCH_ORATOR_ACTOR_ID: "@orator@fmatch.internal.fedi"
          ORATOR_ACTOR_ID: "https://lefine.pro/actors/orator"
          ORATOR_MODEL_ID: "acct:orator@lefine.pro"
          OPENAI_API_KEY: "''${API_KEY}"
          ORATOR_ACTIVITYPUB_KEY_ID: "https://lefine.pro/actors/orator#main-key"
          ORATOR_ACTIVITYPUB_PRIVATE_KEY_PATH: "/results/keys/orator-actor.pem"
          ORATOR_FAST_RESULT_TIMEOUT_SECONDS: "75"
          WEATHER_CHAT_URL: "''${WEATHER_CHAT_URL:-http://weather:8080/v1/chat/completions}"
          OCAWE_SECRETS_FILE: "/results/secrets/secrets.json"
          OCAWE_WORKFLOWS_ROOT: "/workflows/orator"
          OCAWE_TELEMETRY_ENABLED: "true"
          OTEL_SERVICE_NAME: ocawe-orator
          OTEL_EXPORTER_OTLP_ENDPOINT: http://10.4.1.1:4318
          SSL_CERT_FILE: "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          NIX_SSL_CERT_FILE: "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        volumes:
          - ./results:/results
          - ./workflows:/workflows:ro
          - ./results/ocawe-state:/workflows/orator/.ocawe
          - /root/deployments/sireng/reps/ocawe:/ocawe:ro
          - /nix/store:/nix/store:ro
        networks:
          lefine-net:
            aliases:
              - orator-app

      orator:
        image: caddy:2.8-alpine
        container_name: orator
        restart: unless-stopped
        depends_on:
          - orator-app
        environment:
          API_KEY: "''${API_KEY}"
          API_KEYS_PATTERN: "''${API_KEYS_PATTERN}"
        ports:
          - "127.0.0.1:8081:8080"
        volumes:
          - ./Caddyfile:/etc/caddy/Caddyfile:ro
          - ./results:/results:ro
        networks:
          lefine-net:
            aliases:
              - orator

    networks:
      lefine-net:
        external: true
        name: lefine-net
  '';
in
{
  name = "orator";
  target = "/opt/orator";
  compose = "${oratorCompose}";
  project = "orator";
  afterCompose = [ "fmatch" ];
  extraCompose = "";
  healthCheck = "{ orator_app_id=\"$(nerdctl ps -a 2>/dev/null | awk -v name=\"orator-app\" '$NF == name { print $1; exit }')\"; [ -n \"$orator_app_id\" ] && orator_app_ip=\"$(nerdctl inspect \"$orator_app_id\" 2>/dev/null | jq -r '.[0].NetworkSettings.Networks[]?.IPAddress // .[0].NetworkSettings.IPAddress // empty' | head -n1)\" && [ -n \"$orator_app_ip\" ] && curl -fsS \"http://$orator_app_ip:8080/health\" >/dev/null; }";
  healthRetries = 90;
  healthInterval = 2;
  extraPath = [
    pkgs.crystal
    pkgs.gcc
    pkgs.glibc.bin
    pkgs.pkg-config
    pkgs.shards
  ];
  preCompose = ''
    ${runtime.ensureSource "orator runtime"}

    if [ ! -f /opt/orator/.env ]; then
      umask 077
      api_key="orator_$(openssl rand -hex 32)"
      printf 'API_KEY=%s\n' "$api_key" > /opt/orator/.env
      printf 'ORATOR_API_KEY=%s\n' "$api_key" >> /opt/orator/.env
    elif ! grep -q '^API_KEY=' /opt/orator/.env; then
      umask 077
      api_key="orator_$(openssl rand -hex 32)"
      printf 'API_KEY=%s\n' "$api_key" >> /opt/orator/.env
      if ! grep -q '^ORATOR_API_KEY=' /opt/orator/.env; then
        printf 'ORATOR_API_KEY=%s\n' "$api_key" >> /opt/orator/.env
      fi
    elif ! grep -q '^ORATOR_API_KEY=' /opt/orator/.env; then
      api_key="$(awk -F= '/^API_KEY=/ { print $2; exit }' /opt/orator/.env)"
      printf 'ORATOR_API_KEY=%s\n' "$api_key" >> /opt/orator/.env
    fi
    chmod 600 /opt/orator/.env

    mkdir -p /opt/orator/workflows/orator /opt/orator/results /opt/orator/results/ocawe-state
    rm -f /opt/orator/workflows/Cawfile
    chmod 777 /opt/orator/results
    mkdir -p /opt/orator/workflows/orator/.ocawe
    mkdir -p /opt/orator/results/secrets
    mkdir -p /opt/orator/results/keys
    chmod 700 /opt/orator/results/secrets
    chmod 700 /opt/orator/results/keys
    if [ ! -s /opt/orator/results/keys/orator-actor.pem ]; then
      ${pkgs.openssl}/bin/openssl genrsa -out /opt/orator/results/keys/orator-actor.pem 2048 >/dev/null 2>&1
      chmod 600 /opt/orator/results/keys/orator-actor.pem
    fi
    api_key="$(awk -F= '/^API_KEY=/ { print $2; exit }' /opt/orator/.env)"
    secrets_file="/opt/orator/results/secrets/secrets.json"
    if [ ! -f "$secrets_file" ]; then
      printf '[]\n' > "$secrets_file"
    fi
    bootstrap_suffix="$(printf '%s' "$api_key" | sed 's/.*\(............\)$/\1/')"
    if ! jq -e --arg key "$api_key" 'any(.[]?; .value == $key and .scope == "orator" and .kind == "api_key")' "$secrets_file" >/dev/null; then
      tmp_secrets="/opt/orator/results/secrets/secrets.json.tmp"
      jq --arg key "$api_key" --arg name "orator/api-keys/$bootstrap_suffix" --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '. + [{
        "name": $name,
        "value": $key,
        "scope": "orator",
        "kind": "api_key",
        "metadata": {"label": "bootstrap"},
        "active": true,
        "created_at": $created_at,
        "updated_at": $created_at
      }]' "$secrets_file" > "$tmp_secrets"
      mv "$tmp_secrets" "$secrets_file"
    fi
    chmod 600 "$secrets_file"
    api_keys_pattern="$(jq -r '.[]? | select(.scope == "orator" and .kind == "api_key" and (.active // true) != false) | .value' "$secrets_file" | awk '/^[A-Za-z0-9_-]{12,96}$/ { keys = keys ? keys "|" $0 : $0 } END { print keys }')"
    if [ -z "$api_keys_pattern" ]; then
      api_keys_pattern="$api_key"
    fi
    sed -i '/^API_KEYS_PATTERN=/d' /opt/orator/.env
    printf "API_KEYS_PATTERN='%s'\n" "$api_keys_pattern" >> /opt/orator/.env
    container_ip() {
      container_id="$(nerdctl ps -a 2>/dev/null | awk -v name="$1" '$NF == name { print $1; exit }')"
      if [ -z "$container_id" ]; then
        return 1
      fi
      nerdctl inspect "$container_id" 2>/dev/null | jq -r '.[0].NetworkSettings.Networks[]?.IPAddress // .[0].NetworkSettings.IPAddress // empty' | head -n1
    }
	    weather_ip="$(container_ip weather || true)"
	    if [ -n "$weather_ip" ]; then
	      sed -i '/^WEATHER_CHAT_URL=/d' /opt/orator/.env
	      printf 'WEATHER_CHAT_URL=http://%s:8080/v1/chat/completions\n' "$weather_ip" >> /opt/orator/.env
	    fi
	    fmatch_id="$(nerdctl ps -a 2>/dev/null | awk -v name="fmatch" '$NF == name { print $1; exit }')"
	    fmatch_ip=""
	    if [ -n "$fmatch_id" ]; then
	      fmatch_ip="$(nerdctl inspect "$fmatch_id" 2>/dev/null | jq -r '.[0].NetworkSettings.Networks[]?.IPAddress // empty' | awk '/^10[.]4[.]1[.]/{ print; exit }')"
	    fi
	    if [ -n "$fmatch_ip" ]; then
	      sed -i '/^FMATCH_HTTP_HOST=/d' /opt/orator/.env
	      printf 'FMATCH_HTTP_HOST=%s\n' "$fmatch_ip" >> /opt/orator/.env
	      export FMATCH_HTTP_HOST="$fmatch_ip"
	    fi
    mkdir -p /opt/orator/workflows/orator
    cp ${pipelinesRoot}/orator/Cawfile /opt/orator/workflows/orator/Cawfile
    cp -R ${pipelinesRoot}/orator/plugins /opt/orator/workflows/orator/plugins
    awk '
      index($0, "@[Container") == 1 { next }
      /^test[[:space:]]+".*" do[[:space:]]*$/ { in_test = 1; next }
      in_test && /^end[[:space:]]*$/ { in_test = 0; next }
      !in_test { print }
    ' /opt/orator/workflows/orator/Cawfile > /opt/orator/workflows/orator/Cawfile.runtime
    mv /opt/orator/workflows/orator/Cawfile.runtime /opt/orator/workflows/orator/Cawfile
    if [ ! -d "$ocawe_src/lib" ] || [ ! -d "$ocawe_src/lib/rcl" ] || [ ! -d "$ocawe_src/lib/opentelemetry-sdk" ]; then
      if ! command -v shards >/dev/null; then
        echo "Missing shards binary for orator ocawe setup"
        exit 1
      fi
      if ! command -v crystal >/dev/null; then
        echo "Missing crystal binary for orator ocawe setup"
        exit 1
      fi
      rm -rf "$ocawe_src/lib"
      (cd "$ocawe_src" && shards install --skip-postinstall)
    fi
    if [ -d "$ocawe_src/lib/protobuf" ] && [ ! -x "$ocawe_src/lib/protobuf/bin/protoc-gen-crystal" ]; then
      (cd "$ocawe_src/lib/protobuf" && shards build)
    fi
    export PATH="$ocawe_src/lib/protobuf/bin:$PATH"
    if [ ! -d "$ocawe_src/lib" ] || [ ! -d "$ocawe_src/lib/rcl" ]; then
      echo "Failed to install ocawe shards dependencies"
      exit 1
    fi
    sed -i 's/args: \["-lc"/args: ["-c"/g' "$ocawe_src/src/cli/endpoints/runtime.cr"
    ocawe_bin="''${SIRENG_OCAWE_BIN:-$ocawe_src/build/ocawe}"
    if [ ! -x "$ocawe_bin" ] || [ "$ocawe_src/src/cli/endpoints/runtime.cr" -nt "$ocawe_bin" ]; then
      (cd "$ocawe_src" && mkdir -p build && crystal build src/cli/main.cr -o build/ocawe)
    fi
    (
      cd /opt/orator/workflows/orator
      export PKG_CONFIG_PATH="${pkgs.sqlite.dev}/lib/pkgconfig:${pkgs.openssl.dev}/lib/pkgconfig:${pkgs.libyaml.dev}/lib/pkgconfig:${pkgs.pcre2.dev}/lib/pkgconfig:${pkgs.zlib.dev}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
      export LIBRARY_PATH="${pkgs.sqlite.out}/lib:${pkgs.openssl.out}/lib:${pkgs.libyaml}/lib:${pkgs.pcre2}/lib:${pkgs.zlib}/lib:${pkgs.gmp}/lib:''${LIBRARY_PATH:-}"
      export CPATH="${pkgs.sqlite.dev}/include:${pkgs.openssl.dev}/include:${pkgs.libyaml.dev}/include:${pkgs.pcre2.dev}/include:${pkgs.zlib.dev}/include:${pkgs.gmp.dev}/include:''${CPATH:-}"
      export CRYSTAL_PATH="/opt/orator/workflows/orator:$ocawe_src/src:$ocawe_src/lib:$(crystal env CRYSTAL_PATH)"
      "$ocawe_bin" build --release
    )
    cp ${oratorCaddyfile} /opt/orator/Caddyfile

    set -a
    . /opt/orator/.env
    set +a

    nerdctl compose --project-name orator --project-directory /opt/orator -f ${oratorCompose} up -d orator-app
    orator_app_upstream="127.0.0.1:1"
    sed -i "s|__ORATOR_APP_UPSTREAM__|$orator_app_upstream|g" /opt/orator/Caddyfile
    nerdctl rm -f orator 2>/dev/null || true
  '';
  postCompose = ''
    container_ip() {
      container_id="$(nerdctl ps -a 2>/dev/null | awk -v name="$1" '$NF == name { print $1; exit }')"
      if [ -z "$container_id" ]; then
        return 1
      fi
      nerdctl inspect "$container_id" 2>/dev/null | jq -r '.[0].NetworkSettings.Networks[]?.IPAddress // .[0].NetworkSettings.IPAddress // empty' | head -n1
    }
    set -a
    . /opt/orator/.env
    set +a
    sed -i "s|127.0.0.1:1|orator-app:8080|g" /opt/orator/Caddyfile
    orator_app_ip="$(container_ip orator-app)"
    if [ -z "$orator_app_ip" ]; then
      echo "Could not determine orator-app IP"
      exit 1
    fi
    nerdctl rm -f orator 2>/dev/null || true
    nerdctl run -d \
      --name orator \
      --restart unless-stopped \
      --network lefine-net \
      --add-host "orator-app:$orator_app_ip" \
      -p 127.0.0.1:8081:8080 \
      -e API_KEY="$API_KEY" \
      -e API_KEYS_PATTERN="$API_KEYS_PATTERN" \
      -v /opt/orator/Caddyfile:/etc/caddy/Caddyfile:ro \
      -v /opt/orator/results:/results:ro \
      caddy:2.8-alpine
  '';
}
