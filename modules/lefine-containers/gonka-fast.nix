{ pkgs, pipelinesRoot ? ../../../sireng/pipelines, ... }:

let
  runtime = import ./ocawe-runtime.nix { inherit pkgs; };
in
{
  name = "gonka-fast";
  target = "/opt/gonka-fast";
  compose = "/opt/gonka-fast/docker-compose.yml";
  project = "gonka-fast";
  requiresExistingCompose = false;
  afterCompose = [ "fmatch" ];
  extraCompose = "";
  healthCheck = "nerdctl ps --filter name=gonka-fast --format '{{.Status}}' | awk '$0 == \"Up\" { ok = 1 } END { exit ok ? 0 : 1 }'";
  healthRetries = 90;
  healthInterval = 2;
  extraPath = [
    pkgs.crystal
    pkgs.shards
  ];
  preCompose = ''
    ${runtime.skipIfRunning "gonka-fast"}
    ${runtime.ensureSource "gonka-fast build"}

    if [ ! -f /opt/gonka-fast/.env ]; then
      umask 077
      cat > /opt/gonka-fast/.env <<EOF
GONKA_API_KEY=
GONKA_BASE_URL=https://api.gonkagate.com/v1
GONKA_FAST_MODEL=MiniMaxAI/MiniMax-M2.7
GONKA_FAST_TIMEOUT_SECONDS=20
EOF
    fi
    for entry in \
      GONKA_API_KEY= \
      GONKA_BASE_URL=https://api.gonkagate.com/v1 \
      GONKA_FAST_MODEL=MiniMaxAI/MiniMax-M2.7 \
      GONKA_FAST_TIMEOUT_SECONDS=20
    do
      key="''${entry%%=*}"
      if ! grep -q "^$key=" /opt/gonka-fast/.env; then
        printf '%s\n' "$entry" >> /opt/gonka-fast/.env
      fi
    done
    chmod 600 /opt/gonka-fast/.env

    mkdir -p /opt/gonka-fast/workflows/gonka-fast
    cp -p ${pipelinesRoot}/gonka-fast/Cawfile /opt/gonka-fast/workflows/gonka-fast/Cawfile
    if ! nerdctl image inspect gonka-fast:latest >/dev/null 2>&1; then
      ocawe_bin="''${SIRENG_OCAWE_BIN:-$ocawe_src/build/ocawe}"
      if [ ! -x "$ocawe_bin" ]; then
        (cd "$ocawe_src" && mkdir -p build && crystal build src/cli/main.cr -o build/ocawe)
      fi
      (cd /opt/gonka-fast/workflows/gonka-fast && "$ocawe_bin" build --release)
    fi

    cat > /opt/gonka-fast/docker-compose.yml <<'YAML'
services:
  gonka-fast:
    image: gonka-fast:latest
    container_name: gonka-fast
    command: ["--port", "8080"]
    restart: unless-stopped
    environment:
      PORT: "8080"
      GONKA_FAST_ACTOR_ID: "http://gonka-fast:8080/actors/gonka-fast"
      GONKA_BASE_URL: "''${GONKA_BASE_URL}"
      GONKA_API_KEY: "''${GONKA_API_KEY}"
      GONKA_FAST_MODEL: "''${GONKA_FAST_MODEL}"
      GONKA_FAST_TIMEOUT_SECONDS: "''${GONKA_FAST_TIMEOUT_SECONDS}"
      OCAWE_FEDERATION_SIGNATURES_REQUIRED: "false"
      SSL_CERT_FILE: "/etc/ssl/certs/ca-bundle.crt"
    ports:
      - "127.0.0.1:8085:8080"
    volumes:
      - /opt/orator/results:/results
      - /etc/ssl/certs:/etc/ssl/certs:ro
      - /etc/static/ssl/certs:/etc/static/ssl/certs:ro
      - /nix/store:/nix/store:ro
    networks:
      lefine-net:
        aliases:
          - gonka-fast

networks:
  lefine-net:
    external: true
    name: lefine-net
YAML
  '';
  postCompose = "";
}
