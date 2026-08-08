{ pkgs, pipelinesRoot ? ../../../sireng/pipelines, ... }:

let
  runtime = import ./ocawe-runtime.nix { inherit pkgs; };
in
{
  name = "planner";
  target = "/opt/planner";
  compose = "/opt/planner/docker-compose.yml";
  project = "planner";
  requiresExistingCompose = false;
  afterCompose = [
    "fmatch"
    "orator"
    "rotator"
  ];
  extraCompose = "";
  healthCheck = "nerdctl ps --filter name=planner --format '{{.Status}}' | awk '$0 == \"Up\" { ok = 1 } END { exit ok ? 0 : 1 }'";
  healthRetries = 90;
  healthInterval = 2;
  preCompose = ''
    ${runtime.skipIfRunning "planner"}
    ${runtime.ensureSource "planner runtime"}

    ${runtime.reuseOrBuildImage {
      image = "planner";
      preferOcawe = true;
    }}

    mkdir -p /opt/planner/workflows/planner/planner /opt/planner/ocawe-state
    cp -p ${pipelinesRoot}/planner/Cawfile /opt/planner/workflows/planner/Cawfile
    awk 'BEGIN { emit = 1 } /^settings do/ { emit = 0 } emit { print }' \
      /opt/planner/workflows/planner/Cawfile > /opt/planner/workflows/planner/planner/registry.cr
    cp /opt/planner/workflows/planner/planner/registry.cr /opt/planner/workflows/planner/registry.cr
    sed -i '2irequire "planner/registry"' /opt/planner/workflows/planner/Cawfile
    awk 'index($0, "@[Container") != 1 { print }' /opt/planner/workflows/planner/Cawfile > /opt/planner/workflows/planner/Cawfile.runtime
    mv /opt/planner/workflows/planner/Cawfile.runtime /opt/planner/workflows/planner/Cawfile
    cat > /opt/planner/docker-compose.yml <<'YAML'
    services:
      planner:
        image: planner:latest
        container_name: planner
        entrypoint: ["${pkgs.bash}/bin/bash", "-c"]
        command:
          - |
            export PATH="${pkgs.crystal}/bin:${pkgs.shards}/bin:${pkgs.pkg-config}/bin:${pkgs.gcc}/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/app/tools:''${PATH:-}";
            export PKG_CONFIG_PATH="${pkgs.sqlite.dev}/lib/pkgconfig:${pkgs.boehmgc.dev}/lib/pkgconfig:${pkgs.openssl.dev}/lib/pkgconfig:${pkgs.libyaml.dev}/lib/pkgconfig:${pkgs.pcre2.dev}/lib/pkgconfig:${pkgs.zlib.dev}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}";
            export LIBRARY_PATH="${pkgs.sqlite.out}/lib:${pkgs.boehmgc}/lib:${pkgs.openssl.out}/lib:${pkgs.libyaml}/lib:${pkgs.pcre2}/lib:${pkgs.zlib}/lib:${pkgs.gmp}/lib:''${LIBRARY_PATH:-}";
            export CPATH="${pkgs.sqlite.dev}/include:${pkgs.boehmgc.dev}/include:${pkgs.openssl.dev}/include:${pkgs.libyaml.dev}/include:${pkgs.pcre2.dev}/include:${pkgs.zlib.dev}/include:${pkgs.gmp.dev}/include:''${CPATH:-}";
            mkdir -p /tmp /bin;
            ln -sfn ${pkgs.bash}/bin/bash /bin/sh;
            printf 'require "ocawe"\nrequire "registry"\nOcaweCore.run\n' > /tmp/planner_runtime_entry.cr;
            CRYSTAL_PATH=/ocawe/src:/ocawe/lib:/workflows/planner:$(crystal env CRYSTAL_PATH) crystal build /tmp/planner_runtime_entry.cr -o /tmp/plannercore && exec /tmp/plannercore --port 8080
        restart: unless-stopped
        env_file:
          - /opt/rotator/.env
        environment:
          PORT: "8080"
          PLANNER_KEYWORDS_FILE: "/data/datasets/fmatch/key-words.txt"
          PLANNER_MODEL_BASE_URL: "''${GONKA_BASE_URL:-https://api.gonkagate.com/v1}"
          PLANNER_MODEL_API_KEY: "''${GONKA_API_KEY}"
          PLANNER_CLASSIFIED_DISABLED: "true"
          PLANNER_CLASSIFIED_MIN_SCORE: "0.35"
          PLANNER_FMATCH_INBOX_URL: "http://''${FMATCH_HTTP_HOST:-fmatch}:7277/inbox/planner"
          PLANNER_ACTOR_ID: "http://planner:8080/actors/planner"
          PLANNER_FMATCH_ACTOR_ID: "@planner@fmatch.internal.fedi"
          PLANNER_SUBTASK_MAX: "4"
          PLANNER_SUBTASK_WAIT_SECONDS: "45"
          OPENAI_BASE_URL: "''${GONKA_BASE_URL:-https://api.gonkagate.com/v1}"
          OPENAI_API_KEY: "''${GONKA_API_KEY}"
          OCAWE_RESULTS_DIR: "/results"
          OCAWE_WORKFLOWS_ROOT: "/workflows/planner"
          OCAWE_FEDERATION_SIGNATURES_REQUIRED: "false"
          SSL_CERT_FILE: "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          NIX_SSL_CERT_FILE: "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          PATH: "${pkgs.crystal}/bin:${pkgs.shards}/bin:${pkgs.pkg-config}/bin:${pkgs.gcc}/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/app/tools"
        ports:
          - "127.0.0.1:8086:8080"
        volumes:
          - /opt/orator/results:/results
          - /opt/fmatch/datasets:/data/datasets:ro
          - /opt/rotator/.env:/run/secrets/planner/rotator.env:ro
          - /root/deployments/sireng/reps/ocawe:/ocawe:ro
          - /nix/store:/nix/store:ro
          - ./workflows:/workflows
        networks:
          lefine-net:
            aliases:
              - planner

    networks:
      lefine-net:
        external: true
        name: lefine-net
    YAML
    if [ -f /opt/rotator/.env ]; then
      set -a
      . /opt/rotator/.env
      set +a
    fi
  '';
  postCompose = "";
}
