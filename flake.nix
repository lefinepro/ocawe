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

          ocawe = pkgs.crystal.buildCrystalPackage {
            pname = "ocawe";
            version = "26.06.0";
            src = self;
            format = "crystal";
            shardsFile = ./shards.nix;

            crystalBinaries = {
              ocawe = {
                src = "src/cli/main.cr";
                options = [ "--release" "--no-debug" ];
              };
              ocawecore = {
                src = "src/ocawe.cr";
                options = [ "--release" "--no-debug" "-Docawe_runtime_main" ];
              };
            };

            nativeBuildInputs = [
              pkgs.cacert
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

            env = {
              SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
              GIT_SSL_CAINFO = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
            };

            doCheck = false;

            installPhase = ''
              runHook preInstall
              install -Dm755 ocawe "$out/bin/ocawe"
              install -Dm755 ocawecore "$out/bin/ocawecore"
              mkdir -p "$out/share/ocawe"
              cp -R caws scripts "$out/share/ocawe/"
              install -Dm644 README.org "$out/share/doc/ocawe/README.org"
              runHook postInstall
            '';

            doInstallCheck = true;
            installCheckPhase = ''
              runHook preInstallCheck
              "$out/bin/ocawe" --help > /dev/null
              runHook postInstallCheck
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
              pkgs.lua5_4
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

      overlays.default = final: prev: {
        ocawe = self.packages.${prev.system}.ocawe;
        ocawe-oci-image = self.packages.${prev.system}.oci-image;
      };

      nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.services.ocawe;
        in
        {
          options.services.ocawe = {
            enable = lib.mkEnableOption "Ocawe runtime service";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.system}.ocawe;
              defaultText = "ocawe flake package";
              description = "Ocawe package to run.";
            };

            workflowsRoot = lib.mkOption {
              type = lib.types.str;
              default = "/var/lib/ocawe/workflows";
              description = "Directory containing Ocawe Cawfile workflows.";
            };

            port = lib.mkOption {
              type = lib.types.port;
              default = 4111;
              description = "HTTP port for the Ocawe runtime.";
            };

            logLevel = lib.mkOption {
              type = lib.types.enum [ "debug" "warning" "critical" ];
              default = "warning";
              description = "Ocawe runtime log level.";
            };

            environment = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = {};
              description = "Environment variables for the Ocawe runtime service.";
            };

            extraArgs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              description = "Additional arguments passed to ocawecore.";
            };
          };

          config = lib.mkIf cfg.enable {
            environment.systemPackages = [ cfg.package ];

            systemd.services.ocawe = {
              description = "Ocawe runtime";
              wantedBy = [ "multi-user.target" ];
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];
              environment = cfg.environment // {
                SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
              };
              serviceConfig = {
                DynamicUser = true;
                StateDirectory = "ocawe";
                WorkingDirectory = "/var/lib/ocawe";
                Restart = "on-failure";
                RestartSec = "5s";
              };
              script = ''
                exec ${cfg.package}/bin/ocawecore \
                  --port=${toString cfg.port} \
                  --workflows-root=${lib.escapeShellArg cfg.workflowsRoot} \
                  --log-level=${lib.escapeShellArg cfg.logLevel} \
                  ${lib.escapeShellArgs cfg.extraArgs}
              '';
            };
          };
        };

      homeManagerModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.programs.ocawe;
        in
        {
          options.programs.ocawe = {
            enable = lib.mkEnableOption "Ocawe CLI";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.system}.ocawe;
              defaultText = "ocawe flake package";
              description = "Ocawe package to install.";
            };
          };

          config = lib.mkIf cfg.enable {
            home.packages = [ cfg.package ];
          };
        };

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.crystal
              pkgs.pkg-config
              pkgs.shards
              pkgs.lua5_4
              pkgs.ruby
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
          };
        });
    };
}
