{
  description = "Ocawe runtime and container image";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };

          ocawe = pkgs.stdenv.mkDerivation {
            pname = "ocawe";
            version = "26.06.0";
            src = self;

            nativeBuildInputs = [
              pkgs.cacert
              pkgs.crystal
              pkgs.git
              pkgs.pkg-config
              pkgs.shards
            ];

            buildInputs = [
              pkgs.boehmgc
              pkgs.libevent
              pkgs.libxml2
              pkgs.libyaml
              pkgs.openssl
              pkgs.pcre2
              pkgs.sqlite
              pkgs.zlib
            ];

            buildPhase = ''
              runHook preBuild
              export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              export GIT_SSL_CAINFO="$SSL_CERT_FILE"
              shards install --production --ignore-crystal-version
              export CRYSTAL_PATH="$PWD/lib:$(crystal env CRYSTAL_PATH)"
              crystal build src/cli/main.cr --release --no-debug -o ocawe
              crystal build src/ocawe.cr --release --no-debug -Docawe_runtime_main -o ocawecore
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              install -Dm755 ocawe "$out/bin/ocawe"
              install -Dm755 ocawecore "$out/bin/ocawecore"
              runHook postInstall
            '';
          };

          runtimeRoot = pkgs.buildEnv {
            name = "ocawe-runtime-root";
            paths = [
              ocawe
              pkgs.bash
              pkgs.cacert
              pkgs.coreutils
              pkgs.curl
              pkgs.git
              pkgs.nodejs_22
              pkgs.openssh
              pkgs.ruby
              pkgs.sqlite
            ];
          };

          ociImage = pkgs.dockerTools.buildLayeredImage {
            name = "ocawe";
            tag = "latest";
            contents = [ runtimeRoot ];
            config = {
              Env = [
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "OCAWE_WORKFLOWS_ROOT=/workflows"
              ];
              ExposedPorts = {
                "4111/tcp" = {};
              };
              Entrypoint = [ "${ocawe}/bin/ocawe" ];
              Cmd = [
                "--port"
                "4111"
                "--workflows-root"
                "/workflows"
              ];
            };
          };
        in
        {
          inherit ocawe;
          default = ocawe;
          oci-image = ociImage;
        });

      apps = forAllSystems (system:
        let
          pkg = self.packages.${system}.ocawe;
        in
        {
          default = {
            type = "app";
            program = "${pkg}/bin/ocawe";
          };
          ocawecore = {
            type = "app";
            program = "${pkg}/bin/ocawecore";
          };
        });
    };
}
