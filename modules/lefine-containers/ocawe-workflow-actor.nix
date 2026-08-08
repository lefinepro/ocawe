{ pkgs, lib }:

{
  name,
  pipeline,
  hostPort ? null,
  port ? 8080,
  afterCompose ? [
    "fmatch"
    "orator"
  ],
  extraEnvironment ? { },
}:

let
  runtime = import ./ocawe-runtime.nix { inherit pkgs lib; };
  environment = {
    PORT = toString port;
    OCAWE_RESULTS_DIR = "/results";
    OCAWE_FEDERATION_SIGNATURES_REQUIRED = "true";
    SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    NIX_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    PATH = "${pkgs.crystal}/bin:${pkgs.shards}/bin:${pkgs.pkg-config}/bin:${pkgs.gcc}/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/app/tools";
  }
  // extraEnvironment;
  environmentYaml = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (key: value: "      ${key}: ${builtins.toJSON value}") environment
  );
  portsYaml = lib.optionalString (
    hostPort != null
  ) "    ports:\n      - \"127.0.0.1:${toString hostPort}:${toString port}\"\n";
  composeYaml = ''
services:
  ${name}:
    image: ${name}:latest
    container_name: ${name}
    entrypoint: ["${pkgs.bash}/bin/bash", "-c"]
    command:
      - |
        export PATH="${pkgs.crystal}/bin:${pkgs.shards}/bin:${pkgs.pkg-config}/bin:${pkgs.gcc}/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/app/tools:''${PATH:-}";
        export PKG_CONFIG_PATH="${pkgs.sqlite.dev}/lib/pkgconfig:${pkgs.boehmgc.dev}/lib/pkgconfig:${pkgs.openssl.dev}/lib/pkgconfig:${pkgs.libyaml.dev}/lib/pkgconfig:${pkgs.pcre2.dev}/lib/pkgconfig:${pkgs.zlib.dev}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}";
        export LIBRARY_PATH="${pkgs.sqlite.out}/lib:${pkgs.boehmgc}/lib:${pkgs.openssl.out}/lib:${pkgs.libyaml}/lib:${pkgs.pcre2}/lib:${pkgs.zlib}/lib:${pkgs.gmp}/lib:''${LIBRARY_PATH:-}";
        export CPATH="${pkgs.sqlite.dev}/include:${pkgs.boehmgc.dev}/include:${pkgs.openssl.dev}/include:${pkgs.libyaml.dev}/include:${pkgs.pcre2.dev}/include:${pkgs.zlib.dev}/include:${pkgs.gmp.dev}/include:''${CPATH:-}";
        export OCAWE_FEDERATION_ALIAS_URI="$(cat /keys/${name}-actor.did-uri 2>/dev/null || true)";
        mkdir -p /tmp /bin;
        ln -sfn ${pkgs.bash}/bin/bash /bin/sh;
        printf 'require "ocawe"\nrequire "plugins/registry"\nOcaweCore.run\n' > /tmp/${name}_runtime_entry.cr;
        CRYSTAL_PATH=/ocawe/src:/ocawe/lib:/workflows/${name}:$(crystal env CRYSTAL_PATH) crystal build /tmp/${name}_runtime_entry.cr -o /tmp/${name}core && exec /tmp/${name}core --port ${toString port}
    restart: unless-stopped
    environment:
${environmentYaml}
${portsYaml}    volumes:
      - /opt/orator/results:/results
      - /root/deployments/sireng/reps/ocawe:/ocawe:ro
      - /nix/store:/nix/store:ro
      - /opt/${name}/keys:/keys:ro
      - ./workflows:/workflows
    networks:
      lefine-net:
        aliases:
          - ${name}

networks:
  lefine-net:
    external: true
    name: lefine-net
'';
  composeFile = pkgs.writeText "${name}-compose.yml" composeYaml;
in
{
  inherit name afterCompose;
  target = "/opt/${name}";
  compose = "/opt/${name}/docker-compose.yml";
  project = name;
  requiresExistingCompose = false;
  extraCompose = "";
  healthCheck = lib.optionalString (hostPort != null) "curl -fsS http://127.0.0.1:${toString hostPort}/health >/dev/null";
  healthRetries = 90;
  healthInterval = 2;
  preCompose = ''
    ${runtime.skipIfRunning name}
    ${runtime.ensureSource "workflow actor ${name}"}

    ${runtime.reuseOrBuildImage { image = name; }}

    mkdir -p /opt/${name}/workflows/${name} /opt/${name}/keys /opt/${name}/ocawe-state
    cp -p ${pipeline}/Cawfile /opt/${name}/workflows/${name}/Cawfile
    rm -rf /opt/${name}/workflows/${name}/plugins
    cp -rp ${pipeline}/plugins /opt/${name}/workflows/${name}/plugins
    awk 'index($0, "@[Container") != 1 { print }' /opt/${name}/workflows/${name}/Cawfile > /opt/${name}/workflows/${name}/Cawfile.runtime
    mv /opt/${name}/workflows/${name}/Cawfile.runtime /opt/${name}/workflows/${name}/Cawfile
    if [ ! -s /opt/${name}/keys/${name}-actor.pem ]; then
      ${pkgs.openssl}/bin/openssl genrsa -out /opt/${name}/keys/${name}-actor.pem 2048 >/dev/null 2>&1
      chmod 600 /opt/${name}/keys/${name}-actor.pem
    fi
    ${pkgs.openssl}/bin/openssl rsa -in /opt/${name}/keys/${name}-actor.pem -pubout -outform DER -out /opt/${name}/keys/${name}-actor.der >/dev/null 2>&1
    ${pkgs.crystal}/bin/crystal eval '
      alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
      raw = Bytes[0x85_u8, 0x24_u8] + File.read("/opt/${name}/keys/${name}-actor.der").to_slice
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
      File.write("/opt/${name}/keys/${name}-actor.did-uri", "ap://did:key:z#{encoded}/actor\n")
    '
    cp -p ${composeFile} /opt/${name}/docker-compose.yml
  '';
  postCompose = "";
}
