{ pkgs, pipelinesRoot ? ../../../sireng/pipelines, ... }:

let
  runtime = import ./ocawe-runtime.nix { inherit pkgs; };
in
{
  name = "weather";
  target = "/opt/weather";
  compose = "/opt/weather/docker-compose.yml";
  project = "weather";
  requiresExistingCompose = false;
  afterCompose = [
    "fmatch"
    "orator"
  ];
  extraCompose = "";
  healthCheck = "nerdctl ps --filter name=weather --format '{{.Status}}' | awk '$0 == \"Up\" { ok = 1 } END { exit ok ? 0 : 1 }'";
  healthRetries = 90;
  healthInterval = 2;
  preCompose = ''
    ${runtime.skipIfRunning "weather"}
    ${runtime.ensureSource "weather runtime"}

    ${runtime.reuseOrBuildImage { image = "weather"; }}

    mkdir -p /opt/weather/workflows/weather /opt/weather/keys /opt/weather/ocawe-state
    cp -p ${pipelinesRoot}/weather/Cawfile /opt/weather/workflows/weather/Cawfile
    rm -rf /opt/weather/workflows/weather/plugins
    cp -Rp ${pipelinesRoot}/weather/plugins /opt/weather/workflows/weather/plugins
    awk 'index($0, "@[Container") != 1 { print }' /opt/weather/workflows/weather/Cawfile > /opt/weather/workflows/weather/Cawfile.runtime
    mv /opt/weather/workflows/weather/Cawfile.runtime /opt/weather/workflows/weather/Cawfile
    if [ ! -s /opt/weather/keys/weather-actor.pem ]; then
      ${pkgs.openssl}/bin/openssl genrsa -out /opt/weather/keys/weather-actor.pem 2048 >/dev/null 2>&1
      chmod 600 /opt/weather/keys/weather-actor.pem
    fi
    ${pkgs.openssl}/bin/openssl rsa -in /opt/weather/keys/weather-actor.pem -pubout -outform DER -out /opt/weather/keys/weather-actor.der >/dev/null 2>&1
    ${pkgs.crystal}/bin/crystal eval '
      alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
      raw = Bytes[0x85_u8, 0x24_u8] + File.read("/opt/weather/keys/weather-actor.der").to_slice
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
      File.write("/opt/weather/keys/weather-actor.did-uri", "ap://did:key:z#{encoded}/actor\n")
    '
    cat > /opt/weather/docker-compose.yml <<'YAML'
    services:
      weather:
        image: weather:latest
        container_name: weather
        entrypoint: ["${pkgs.bash}/bin/bash", "-c"]
        command:
          - |
            export PATH="${pkgs.crystal}/bin:${pkgs.shards}/bin:${pkgs.pkg-config}/bin:${pkgs.gcc}/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/app/tools:''${PATH:-}";
            export PKG_CONFIG_PATH="${pkgs.sqlite.dev}/lib/pkgconfig:${pkgs.boehmgc.dev}/lib/pkgconfig:${pkgs.openssl.dev}/lib/pkgconfig:${pkgs.libyaml.dev}/lib/pkgconfig:${pkgs.pcre2.dev}/lib/pkgconfig:${pkgs.zlib.dev}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}";
            export LIBRARY_PATH="${pkgs.sqlite.out}/lib:${pkgs.boehmgc}/lib:${pkgs.openssl.out}/lib:${pkgs.libyaml}/lib:${pkgs.pcre2}/lib:${pkgs.zlib}/lib:${pkgs.gmp}/lib:''${LIBRARY_PATH:-}";
            export CPATH="${pkgs.sqlite.dev}/include:${pkgs.boehmgc.dev}/include:${pkgs.openssl.dev}/include:${pkgs.libyaml.dev}/include:${pkgs.pcre2.dev}/include:${pkgs.zlib.dev}/include:${pkgs.gmp.dev}/include:''${CPATH:-}";
            export OCAWE_FEDERATION_ALIAS_URI="acct:openmeteo@fed.lefine.pro";
            export OCAWE_FEDERATION_ACTOR_HANDLE="@openmeteo@fed.lefine.pro";
            export OCAWE_FEDERATION_ACTOR_NAME="openmeteo";
            export OCAWE_FEDERATION_ACTOR_SUMMARY="OpenMeteo forecast workflow";
            export OCAWE_FEDERATION_TAGS="openmeteo,open-meteo,weather,forecast,temperature,rain,wind,humidity,pressure";
            export OCAWE_FEDERATION_RESOURCE_CONFORMS_TO="https://fmatch/marketplace/resources/weather";
            export OCAWE_FEDERATION_ACTION="deliverService";
            export OCAWE_FEDERATION_PURPOSE="request";
            mkdir -p /tmp /bin;
            ln -sfn ${pkgs.bash}/bin/bash /bin/sh;
            printf 'require "ocawe"\nrequire "plugins/registry"\nOcaweCore.run\n' > /tmp/weather_runtime_entry.cr;
            CRYSTAL_PATH=/ocawe/src:/ocawe/lib:/workflows/weather:$(crystal env CRYSTAL_PATH) crystal build /tmp/weather_runtime_entry.cr -o /tmp/weathercore && cd /workflows/weather && exec /tmp/weathercore --port 8080
        restart: unless-stopped
        environment:
          PORT: "8080"
          WEATHER_DEFAULT_LOCATION: "New York"
          OCAWE_RESULTS_DIR: "/results"
          OCAWE_FEDERATION_SIGNATURES_REQUIRED: "true"
          SSL_CERT_FILE: "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          NIX_SSL_CERT_FILE: "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          PATH: "${pkgs.crystal}/bin:${pkgs.shards}/bin:${pkgs.pkg-config}/bin:${pkgs.gcc}/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/app/tools"
        ports:
          - "127.0.0.1:8083:8080"
        volumes:
          - /opt/orator/results:/results
          - /root/deployments/sireng/reps/ocawe:/ocawe:ro
          - /nix/store:/nix/store:ro
          - /opt/weather/keys:/keys:ro
          - ./workflows:/workflows
        networks:
          lefine-net:
            aliases:
              - weather

    networks:
      lefine-net:
        external: true
        name: lefine-net
    YAML
  '';
  postCompose = "";
}
