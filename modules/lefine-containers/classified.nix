{ pkgs, pipelinesRoot ? ../../../sireng/pipelines, ... }:

let
  runtime = import ./ocawe-runtime.nix { inherit pkgs; };
in
{
  name = "classified";
  target = "/opt/classified";
  compose = "/opt/classified/docker-compose.yml";
  project = "classified";
  requiresExistingCompose = false;
  afterCompose = [
    "fmatch"
    "orator"
  ];
  extraCompose = "";
  healthCheck = "nerdctl ps --filter name=classified --format '{{.Status}}' | awk '$0 == \"Up\" { ok = 1 } END { exit ok ? 0 : 1 }'";
  healthRetries = 90;
  healthInterval = 2;
  preCompose = ''
    ${runtime.skipIfRunning "classified"}
    ${runtime.ensureSource "classified runtime"}

    ${runtime.reuseOrBuildImage { image = "classified"; }}

    if [ ! -f /opt/classified/.env ]; then
      umask 077
      {
        printf 'CLASSIFIED_MODEL_MODE=chat\n'
        printf 'CLASSIFIED_MODEL=chat_completion/minimaxai/minimax-m2.7\n'
        printf 'CLASSIFIED_MODEL_BASE_URL=https://api.gonkagate.com/v1\n'
        printf 'CLASSIFIED_MODEL_HOST=https://router.huggingface.co/hf-inference/models/MoritzLaurer/ModernBERT-large-zeroshot-v2.0\n'
        printf 'API_KEY=\n'
        printf 'CLASSIFIED_MODEL_API_KEY=\n'
        printf 'CLASSIFIED_HEURISTIC_FALLBACK=true\n'
        printf 'CLASSIFIED_LABELS=timer,proxy,weather,search,planning,code,debug,deploy,research,writing,translation,vision,audio,data,database,api,frontend,backend,devops,security,math,reasoning,summarize,chat,general\n'
        printf 'CLASSIFIED_TIMEOUT_SECONDS=30\n'
      } > /opt/classified/.env
    fi
    chmod 600 /opt/classified/.env

    mkdir -p /opt/classified/workflows/classified/classified /opt/classified/ocawe-state
    cp -p ${pipelinesRoot}/classified/Cawfile /opt/classified/workflows/classified/Cawfile
    awk 'BEGIN { emit = 1 } /^settings do/ { emit = 0 } emit { print }' \
      /opt/classified/workflows/classified/Cawfile > /opt/classified/workflows/classified/classified/registry.cr
    cp /opt/classified/workflows/classified/classified/registry.cr /opt/classified/workflows/classified/registry.cr
    sed -i '2irequire "classified/registry"' /opt/classified/workflows/classified/Cawfile
    awk 'index($0, "@[Container") != 1 { print }' /opt/classified/workflows/classified/Cawfile > /opt/classified/workflows/classified/Cawfile.runtime
    mv /opt/classified/workflows/classified/Cawfile.runtime /opt/classified/workflows/classified/Cawfile
    cat > /opt/classified/docker-compose.yml <<'YAML'
    services:
      classified:
        image: classified:latest
        container_name: classified
        entrypoint: ["${pkgs.bash}/bin/bash", "-c"]
        command:
          - |
            export PATH="${pkgs.crystal}/bin:${pkgs.shards}/bin:${pkgs.pkg-config}/bin:${pkgs.gcc}/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/app/tools:''${PATH:-}";
            export PKG_CONFIG_PATH="${pkgs.sqlite.dev}/lib/pkgconfig:${pkgs.boehmgc.dev}/lib/pkgconfig:${pkgs.openssl.dev}/lib/pkgconfig:${pkgs.libyaml.dev}/lib/pkgconfig:${pkgs.pcre2.dev}/lib/pkgconfig:${pkgs.zlib.dev}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}";
            export LIBRARY_PATH="${pkgs.sqlite.out}/lib:${pkgs.boehmgc}/lib:${pkgs.openssl.out}/lib:${pkgs.libyaml}/lib:${pkgs.pcre2}/lib:${pkgs.zlib}/lib:${pkgs.gmp}/lib:''${LIBRARY_PATH:-}";
            export CPATH="${pkgs.sqlite.dev}/include:${pkgs.boehmgc.dev}/include:${pkgs.openssl.dev}/include:${pkgs.libyaml.dev}/include:${pkgs.pcre2.dev}/include:${pkgs.zlib.dev}/include:${pkgs.gmp.dev}/include:''${CPATH:-}";
            export OCAWE_FEDERATION_ALIAS_URI="https://classified/actors/classified";
            export OCAWE_FEDERATION_ACTOR_NAME="classified";
            export OCAWE_FEDERATION_ACTOR_SUMMARY="Zero-shot request classification workflow";
            export OCAWE_FEDERATION_TAGS="classification,zero-shot,modernbert,huggingface,routing";
            export OCAWE_FEDERATION_RESOURCE_CONFORMS_TO="https://fmatch/marketplace/resources/classified";
            export OCAWE_FEDERATION_ACTION="deliverService";
            export OCAWE_FEDERATION_PURPOSE="request";
            mkdir -p /tmp /bin;
            ln -sfn ${pkgs.bash}/bin/bash /bin/sh;
            printf 'require "ocawe"\nrequire "registry"\nOcaweCore.run\n' > /tmp/classified_runtime_entry.cr;
            CRYSTAL_PATH=/ocawe/src:/ocawe/lib:/workflows/classified:$(crystal env CRYSTAL_PATH) crystal build /tmp/classified_runtime_entry.cr -o /tmp/classifiedcore && exec /tmp/classifiedcore --port 8080
        restart: unless-stopped
        env_file:
          - /opt/classified/.env
        environment:
          PORT: "8080"
          CLASSIFIED_ACTOR_ID: "http://classified:8080/actors/classified"
          CLASSIFIED_MODEL_MODE: "chat"
          CLASSIFIED_MODEL: "chat_completion/minimaxai/minimax-m2.7"
          CLASSIFIED_MODEL_BASE_URL: "''${GONKA_BASE_URL:-https://api.gonkagate.com/v1}"
          CLASSIFIED_MODEL_API_KEY: "''${GONKA_API_KEY}"
          CLASSIFIED_HEURISTIC_FALLBACK: "true"
          OCAWE_FEDERATION_SIGNATURES_REQUIRED: "false"
          SSL_CERT_FILE: "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          NIX_SSL_CERT_FILE: "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          PATH: "${pkgs.crystal}/bin:${pkgs.shards}/bin:${pkgs.pkg-config}/bin:${pkgs.gcc}/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/app/tools"
        ports:
          - "127.0.0.1:8088:8080"
        volumes:
          - /root/deployments/sireng/reps/ocawe:/ocawe:ro
          - /nix/store:/nix/store:ro
          - ./workflows:/workflows
        networks:
          lefine-net:
            aliases:
              - classified

    networks:
      lefine-net:
        external: true
        name: lefine-net
    YAML
  '';
  postCompose = "";
}
