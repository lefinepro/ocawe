{ pkgs, pipelinesRoot ? ../../../sireng/pipelines, ... }:

let
  runtime = import ./ocawe-runtime.nix { inherit pkgs; };
in
{
  name = "rotator";
  target = "/opt/rotator";
  compose = "${./rotator-compose.yml}";
  project = "rotator";
  afterCompose = [
    "fmatch"
    "orator"
  ];
  healthCheck = "nerdctl ps --filter name=rotator --format '{{.Status}}' | awk '$0 == \"Up\" { ok = 1 } END { exit ok ? 0 : 1 }'";
  healthRetries = 90;
  healthInterval = 2;
  extraCompose = ''
    services:
      rotator:
        entrypoint: ["${pkgs.bash}/bin/bash", "-c"]
        env_file:
          - /opt/rotator/.env
        command:
          - |
            export PATH="${pkgs.crystal}/bin:${pkgs.shards}/bin:${pkgs.pkg-config}/bin:${pkgs.gcc}/bin:${pkgs.coreutils}/bin:${pkgs.postgresql_16}/bin:/usr/bin:/bin:/app/tools:''${PATH:-}";
            export PKG_CONFIG_PATH="${pkgs.sqlite.dev}/lib/pkgconfig:${pkgs.boehmgc.dev}/lib/pkgconfig:${pkgs.openssl.dev}/lib/pkgconfig:${pkgs.libyaml.dev}/lib/pkgconfig:${pkgs.pcre2.dev}/lib/pkgconfig:${pkgs.zlib.dev}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}";
            export LIBRARY_PATH="${pkgs.sqlite.out}/lib:${pkgs.boehmgc}/lib:${pkgs.openssl.out}/lib:${pkgs.libyaml}/lib:${pkgs.pcre2}/lib:${pkgs.zlib}/lib:${pkgs.gmp}/lib:''${LIBRARY_PATH:-}";
            export CPATH="${pkgs.sqlite.dev}/include:${pkgs.boehmgc.dev}/include:${pkgs.openssl.dev}/include:${pkgs.libyaml.dev}/include:${pkgs.pcre2.dev}/include:${pkgs.zlib.dev}/include:${pkgs.gmp.dev}/include:''${CPATH:-}";
            mkdir -p /tmp /bin;
            cd /data;
            ln -sfn ${pkgs.bash}/bin/bash /bin/sh;
            printf 'require "ocawe"\nrequire "registry"\nOcaweCore.run\n' > /tmp/rotator_runtime_entry.cr;
            CRYSTAL_PATH=/ocawe/src:/ocawe/lib:/data/workflows/rotator:$(crystal env CRYSTAL_PATH) crystal build /tmp/rotator_runtime_entry.cr -o /tmp/rotatorcore && exec /tmp/rotatorcore --port 8080
        environment:
          PATH: "${pkgs.crystal}/bin:${pkgs.shards}/bin:${pkgs.pkg-config}/bin:${pkgs.gcc}/bin:${pkgs.coreutils}/bin:${pkgs.postgresql_16}/bin:/usr/bin:/bin:/app/tools"
          SSL_CERT_FILE: "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          NIX_SSL_CERT_FILE: "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        volumes:
          - /root/deployments/sireng/reps/ocawe:/ocawe:ro
          - /nix/store:/nix/store:ro
  '';
  preCompose = ''
    ${runtime.ensureSource "rotator runtime"}

    if [ ! -f /opt/rotator/.env ]; then
      umask 077
      {
        printf 'GONKA_API_KEY=\n'
        printf 'GONKA_BASE_URL=https://api.gonkagate.com/v1\n'
        printf 'ROTATOR_MODELS_DEV_URL=https://models.dev/api.json\n'
        printf 'ROTATOR_GONKA_PRICING_URL=https://gonkagate.com/en/pricing\n'
        printf 'ROTATOR_DATASET_ROOT=/data/datasets\n'
        printf 'ROTATOR_MARKETPLACE_PROPOSALS_ENABLED=true\n'
        printf 'ROTATOR_PROVIDER_TIMEOUT_SECONDS=12\n'
        printf 'ROTATOR_FALLBACK_MODEL_CANDIDATES=openrouter/free@openrouter\n'
        printf 'ROTATOR_POSTGRES_DSN=\n'
      } > /opt/rotator/.env
    fi

    for key in \
      OPENAI_API_KEY \
      OPENAI_BASE_URL \
      MLOPASS_API_KEY \
      MLOPASS_BASE_URL \
      ROTATOR_MLOPASS_API_KEY \
      ROTATOR_MLOPASS_MODEL_CANDIDATES \
      ROTATOR_MLOPASS_LIMIT_LABEL
    do
      sed -i "/^$key=/d" /opt/rotator/.env
    done

    for entry in \
      GONKA_API_KEY= \
      GONKA_BASE_URL=https://api.gonkagate.com/v1 \
      ROTATOR_MODELS_DEV_URL=https://models.dev/api.json \
      ROTATOR_GONKA_PRICING_URL=https://gonkagate.com/en/pricing \
      ROTATOR_DATASET_ROOT=/data/datasets \
      ROTATOR_MARKETPLACE_PROPOSALS_ENABLED=true \
      ROTATOR_PROVIDER_TIMEOUT_SECONDS=12 \
      ROTATOR_FALLBACK_MODEL_CANDIDATES=openrouter/free@openrouter \
      ROTATOR_POSTGRES_DSN=
    do
      key="''${entry%%=*}"
      if ! grep -q "^$key=" /opt/rotator/.env; then
        printf '%s\n' "$entry" >> /opt/rotator/.env
      fi
    done

    chmod 600 /opt/rotator/.env
    sed -i '/^FMATCH_HTTP_HOST=/d' /opt/rotator/.env
    sed -i '/^ROTATOR_FOLLOW_INBOX=/d' /opt/rotator/.env
    printf 'FMATCH_HTTP_HOST=fmatch\n' >> /opt/rotator/.env
    printf 'ROTATOR_FOLLOW_INBOX=http://fmatch:7277/inbox/orator\n' >> /opt/rotator/.env
    export FMATCH_HTTP_HOST=fmatch
    ${runtime.reuseOrBuildImage {
      image = "rotator";
      preferOcawe = true;
    }}

    mkdir -p /opt/rotator/data/datasets
    mkdir -p /opt/rotator/secrets
    chmod 700 /opt/rotator/secrets
    mkdir -p /opt/rotator/data/workflows/rotator/rotator
    mkdir -p /opt/rotator/workflows/rotator
    ln -sfn /root/deployments/sireng/reps/ocawe /root/deployments/sireng-rotator-ocawe
    cp ${pipelinesRoot}/rotator/Cawfile /opt/rotator/data/workflows/rotator/Cawfile
    awk 'BEGIN { emit = 1 } /^settings do/ { emit = 0 } emit { print }' /opt/rotator/data/workflows/rotator/Cawfile > /opt/rotator/data/workflows/rotator/rotator/registry.cr
    cp /opt/rotator/data/workflows/rotator/rotator/registry.cr /opt/rotator/data/workflows/rotator/registry.cr
    sed -i '2irequire "rotator/registry"' /opt/rotator/data/workflows/rotator/Cawfile
    awk 'index($0, "@[Container") != 1 { print }' /opt/rotator/data/workflows/rotator/Cawfile > /opt/rotator/data/workflows/rotator/Cawfile.runtime
    mv /opt/rotator/data/workflows/rotator/Cawfile.runtime /opt/rotator/data/workflows/rotator/Cawfile
    cp -a /opt/rotator/data/workflows/rotator/. /opt/rotator/workflows/rotator/
    set -a
    . /opt/rotator/.env
    set +a
  '';
  postCompose = "";
}
