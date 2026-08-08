{ pkgs, ... }:

let
  runtime = import ./ocawe-runtime.nix { inherit pkgs; };
in
{
  name = "autoproxygen";
  target = "/opt/autoproxygen";
  compose = "/opt/autoproxygen/docker-compose.yml";
  project = "autoproxygen";
  requiresExistingCompose = false;
  afterCompose = [ ];
  extraCompose = "";
  extraPath = [
    pkgs.crystal
    pkgs.shards
    pkgs.pkg-config
    pkgs.gcc
  ];
  preCompose = ''
    ${runtime.skipIfRunning "autoproxygen"}
    ${runtime.ensureSource "autoproxygen build context"}

    mkdir -p /opt/autoproxygen/src /opt/autoproxygen/cache /opt/autoproxygen/config
    rm -rf /opt/autoproxygen/src/autoproxygen /opt/autoproxygen/src/aptok
    cp -rp ${../../../autoproxygen} /opt/autoproxygen/src/autoproxygen
    cp -rp ${../../../aptok} /opt/autoproxygen/src/aptok
    chmod -R u+w /opt/autoproxygen/src/autoproxygen /opt/autoproxygen/src/aptok

    (
      cd /opt/autoproxygen/src/autoproxygen
      export PKG_CONFIG_PATH="${pkgs.sqlite.dev}/lib/pkgconfig:${pkgs.boehmgc.dev}/lib/pkgconfig:${pkgs.openssl.dev}/lib/pkgconfig:${pkgs.libyaml.dev}/lib/pkgconfig:${pkgs.pcre2.dev}/lib/pkgconfig:${pkgs.zlib.dev}/lib/pkgconfig:''${PKG_CONFIG_PATH:-}"
      export LIBRARY_PATH="${pkgs.sqlite.out}/lib:${pkgs.boehmgc}/lib:${pkgs.openssl.out}/lib:${pkgs.libyaml}/lib:${pkgs.pcre2}/lib:${pkgs.zlib}/lib:${pkgs.gmp}/lib:''${LIBRARY_PATH:-}"
      export CPATH="${pkgs.sqlite.dev}/include:${pkgs.boehmgc.dev}/include:${pkgs.openssl.dev}/include:${pkgs.libyaml.dev}/include:${pkgs.pcre2.dev}/include:${pkgs.zlib.dev}/include:${pkgs.gmp.dev}/include:''${CPATH:-}"
      shards --production install
      shards build --release
    )

    ${runtime.reuseOrBuildImage { image = "autoproxygen"; dockerfileAware = true; }}

    cat > /opt/autoproxygen/docker-compose.yml <<'YAML'
    services:
      autoproxygen:
        image: autoproxygen:latest
        container_name: autoproxygen
        entrypoint: ["${pkgs.bash}/bin/bash", "-c"]
        command:
          - |
            export HOME=/data;
            export PATH="${pkgs.sing-box}/bin:${pkgs.curl}/bin:${pkgs.coreutils}/bin:/usr/bin:/bin";
            cd /app/autoproxygen;
            exec ./bin/autoproxygen run --federate --federate-host=0.0.0.0 --federate-port=4077 --federate-origin=http://autoproxygen:4077
        restart: unless-stopped
        environment:
          SSL_CERT_FILE: "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          NIX_SSL_CERT_FILE: "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        volumes:
          - /opt/autoproxygen/src/autoproxygen:/app/autoproxygen:ro
          - /opt/autoproxygen/cache:/data/.cache/autoproxygen
          - /opt/autoproxygen/config:/data/.config/autoproxygen
          - /nix/store:/nix/store:ro
        networks:
          lefine-net:
            aliases:
              - autoproxygen

    networks:
      lefine-net:
        external: true
        name: lefine-net
    YAML
  '';
  postCompose = "";
}
