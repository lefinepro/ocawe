{ pkgs, pipelinesRoot ? ../../../sireng/pipelines, ... }:

let
  runtime = import ./ocawe-runtime.nix { inherit pkgs; };
in
{
  name = "executor";
  target = "/opt/executor";
  compose = "/opt/executor/docker-compose.yml";
  project = "executor";
  requiresExistingCompose = false;
  afterCompose = [
    "fmatch"
    "orator"
  ];
  extraCompose = "";
  healthCheck = "nerdctl ps --filter name=executor --format '{{.Status}}' | awk '$0 == \"Up\" { ok = 1 } END { exit ok ? 0 : 1 }'";
  healthRetries = 90;
  healthInterval = 2;
  preCompose = ''
    ${runtime.skipIfRunning "executor"}
    ${runtime.ensureSource "executor runtime"}

    if nerdctl image inspect executor:latest >/dev/null 2>&1; then
      :
    else
      ${runtime.reuseOrBuildImage {
        image = "executor";
        preferOcawe = true;
      }}
    fi

    mkdir -p /opt/executor/workflows/executor /opt/executor/keys /opt/executor/codex /opt/executor/data /opt/executor/ocawe-state
    cp -p ${pipelinesRoot}/executor/Cawfile /opt/executor/workflows/executor/Cawfile
    awk 'index($0, "@[Container") != 1 { print }' /opt/executor/workflows/executor/Cawfile > /opt/executor/workflows/executor/Cawfile.runtime
    mv /opt/executor/workflows/executor/Cawfile.runtime /opt/executor/workflows/executor/Cawfile
    if [ ! -s /opt/executor/keys/executor-actor.pem ]; then
      ${pkgs.openssl}/bin/openssl genrsa -out /opt/executor/keys/executor-actor.pem 2048 >/dev/null 2>&1
      chmod 600 /opt/executor/keys/executor-actor.pem
    fi
    ${pkgs.openssl}/bin/openssl rsa -in /opt/executor/keys/executor-actor.pem -pubout -outform DER -out /opt/executor/keys/executor-actor.der >/dev/null 2>&1
    ${pkgs.crystal}/bin/crystal eval '
      alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
      raw = Bytes[0x85_u8, 0x24_u8] + File.read("/opt/executor/keys/executor-actor.der").to_slice
      digits = [0]
      raw.each do |byte|
        carry = byte.to_i
        digits.size.times do |index|
          carry += digits[index] << 8
          digits[index] = carry % 58
          carry //= 58
        end
        while carry > 0
          digits << carry % 58
          carry //= 58
        end
      end
      zeroes = raw.take_while(&.== 0).size
      encoded = "1" * zeroes + digits.reverse.map { |digit| alphabet[digit] }.join
      File.write("/opt/executor/keys/executor-actor.did-uri", "ap://did:key:z#{encoded}/actor\n")
    '
    cat > /opt/executor/docker-compose.yml <<'YAML'
    services:
      executor:
        image: executor:latest
        container_name: executor
        entrypoint: ["${pkgs.bash}/bin/bash", "-c"]
        command:
          - |
            export PATH="${pkgs.crystal}/bin:${pkgs.shards}/bin:${pkgs.pkg-config}/bin:${pkgs.gcc}/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/app/tools:''${PATH:-}";
            export PKG_CONFIG_PATH="${pkgs.sqlite.dev}/lib/pkgconfig:${pkgs.boehmgc.dev}/lib/pkgconfig:${pkgs.openssl.dev}/lib/pkgconfig:${pkgs.libyaml.dev}/lib/pkgconfig:${pkgs.pcre2.dev}/lib/pkgconfig:${pkgs.zlib.dev}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}";
            export LIBRARY_PATH="${pkgs.sqlite.out}/lib:${pkgs.boehmgc}/lib:${pkgs.openssl.out}/lib:${pkgs.libyaml}/lib:${pkgs.pcre2}/lib:${pkgs.zlib}/lib:${pkgs.gmp}/lib:''${LIBRARY_PATH:-}";
            export CPATH="${pkgs.sqlite.dev}/include:${pkgs.boehmgc.dev}/include:${pkgs.openssl.dev}/include:${pkgs.libyaml.dev}/include:${pkgs.pcre2.dev}/include:${pkgs.zlib.dev}/include:${pkgs.gmp.dev}/include:''${CPATH:-}";
            export OCAWE_FEDERATION_ALIAS_URI="$(cat /keys/executor-actor.did-uri 2>/dev/null || true)";
            export OCAWE_FEDERATION_ACTOR_HANDLE="@coder@fed.lefine.pro";
            export OCAWE_FEDERATION_ACTOR_NAME="coder";
            export OCAWE_FEDERATION_ACTOR_SUMMARY="Codex ACP coding executor";
            export OCAWE_FEDERATION_TAGS="coder,codex,code,debug,reasoning,thinks";
            export OCAWE_FEDERATION_RESOURCE_CONFORMS_TO="https://fmatch/marketplace/resources/model";
            export OCAWE_FEDERATION_ACTION="deliverService";
            export OCAWE_FEDERATION_PURPOSE="request";
            mkdir -p /tmp /bin /data/executor "''${CODEX_HOME:-/var/lib/executor/codex}";
            ln -sfn ${pkgs.bash}/bin/bash /bin/sh;
            if ! command -v codex >/dev/null 2>&1; then
              echo "codex command is missing; build executor image with codex-acp or mount codex into PATH" >&2;
            fi;
            printf 'require "ocawe"\nOcaweCore.run\n' > /tmp/executor_runtime_entry.cr;
            CRYSTAL_PATH=/ocawe/src:/ocawe/lib:/workflows/executor:$(crystal env CRYSTAL_PATH) crystal build /tmp/executor_runtime_entry.cr -o /tmp/executorcore && cd /workflows/executor && exec /tmp/executorcore --port 8080
        restart: unless-stopped
        env_file:
          - /opt/executor/.env
        environment:
          PORT: "8080"
          CODEX_HOME: "''${CODEX_HOME:-/var/lib/executor/codex}"
          OCAWE_AGENT_PLACEMENT: "''${OCAWE_AGENT_PLACEMENT:-container}"
          OCAWE_AGENT_CONTAINER_IMAGE: "''${OCAWE_AGENT_CONTAINER_IMAGE:-executor:latest}"
          OCAWE_CONTAINER_TOOL: "''${OCAWE_CONTAINER_TOOL:-nerdctl}"
          OCAWE_AGENT_WORKSPACE_PATH: "''${OCAWE_AGENT_WORKSPACE_PATH:-/workspace/lefinepro}"
          OCAWE_AGENT_HOST_PATH: "''${OCAWE_AGENT_HOST_PATH:-/opt/kefine2-deploy/workspace}"
          OCAWE_AGENT_WRITE_POLICY: "''${OCAWE_AGENT_WRITE_POLICY:-write}"
          OCAWE_RESULTS_DIR: "/results"
          OCAWE_FEDERATION_SIGNATURES_REQUIRED: "false"
          SSL_CERT_FILE: "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          NIX_SSL_CERT_FILE: "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          PATH: "${pkgs.crystal}/bin:${pkgs.shards}/bin:${pkgs.pkg-config}/bin:${pkgs.gcc}/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/app/tools"
        ports:
          - "127.0.0.1:8088:8080"
        volumes:
          - /opt/orator/results:/results
          - /root/deployments/sireng/reps/ocawe:/ocawe:ro
          - /nix/store:/nix/store:ro
          - /opt/executor/keys:/keys:ro
          - /opt/executor/codex:/var/lib/executor/codex
          - /opt/executor/data:/data/executor
          - ''${OCAWE_AGENT_HOST_PATH:-/opt/kefine2-deploy/workspace}:''${OCAWE_AGENT_WORKSPACE_PATH:-/workspace/lefinepro}
          - ./workflows:/workflows
        networks:
          lefine-net:
            aliases:
              - executor

    networks:
      lefine-net:
        external: true
        name: lefine-net
    YAML
    if [ ! -f /opt/executor/.env ]; then
      umask 077
      {
        printf 'CODEX_HOME=/var/lib/executor/codex\n'
        printf 'OPENAI_API_KEY=\n'
      } > /opt/executor/.env
    fi
    chmod 600 /opt/executor/.env
  '';
  postCompose = "";
}
