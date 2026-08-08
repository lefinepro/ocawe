{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.lefine.containers;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  pipelinesRoot = ../../sireng/pipelines;

  allComposeSpecs =
    map
      (
        file:
        import file {
          inherit lib pkgs pipelinesRoot;
          containersCfg = cfg;
        }
      )
      [
        ./lefine-containers/source-forgejo.nix
        ../../crada/deployment/sireng-compose.nix
        ../../fmatch/deployment/sireng-compose.nix
        ../../kefine2/deployment/sireng-compose.nix
        ./lefine-containers/orator.nix
        ./lefine-containers/planner.nix
        ./lefine-containers/weather.nix
        ./lefine-containers/executor.nix
        ./lefine-containers/autoproxygen.nix
        ./lefine-containers/proxy.nix
        ./lefine-containers/rotator.nix
        ./lefine-containers/public-caddy.nix
        ./lefine-containers/maddy-webmail.nix
        ./lefine-containers/legggit-landing.nix
      ];
  composeSpecs = builtins.filter (
    spec: !(builtins.elem spec.name cfg.disabledStacks)
  ) allComposeSpecs;
  enabledStackNames = map (spec: spec.name) composeSpecs;
  enabledAfterCompose =
    spec: builtins.filter (name: builtins.elem name enabledStackNames) spec.afterCompose;

  composeService =
    spec:
    let
      extraComposeFile =
        if spec.extraCompose == "" then
          null
        else
          pkgs.writeText "${spec.name}-compose.override.yml" spec.extraCompose;
      composeFiles =
        "-f ${lib.escapeShellArg spec.compose}"
        + lib.optionalString (extraComposeFile != null) " -f ${extraComposeFile}";
      healthCheck = spec.healthCheck or "";
      healthRetries = spec.healthRetries or 60;
      healthInterval = spec.healthInterval or 2;
    in
    {
      description = "Apply ${spec.name} compose stack with nerdctl";
      wantedBy = [ "multi-user.target" ];
      after = [
        "containerd.service"
        "lefine-buildkit.service"
        "lefine-container-networks.service"
      ]
      ++ map (name: "lefine-compose-${name}.service") (enabledAfterCompose spec);
      requires = [
        "containerd.service"
        "lefine-buildkit.service"
        "lefine-container-networks.service"
      ]
      ++ map (name: "lefine-compose-${name}.service") (enabledAfterCompose spec);
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = spec.target;
      };
      path = [
        pkgs.bash
        pkgs.coreutils
        pkgs.curl
        pkgs.git
        pkgs.gawk
        pkgs.gnugrep
        pkgs.gnused
        pkgs.iptables
        pkgs.jq
        pkgs.nerdctl
        pkgs.nix
        pkgs.openssl
      ]
      ++ (spec.extraPath or [ ]);
      script = ''
        test -d ${lib.escapeShellArg spec.target}
        ${lib.optionalString (spec.requiresExistingCompose or true
        ) "test -f ${lib.escapeShellArg spec.compose}"}
        ${spec.preCompose}
        nerdctl compose --project-name ${lib.escapeShellArg spec.project} --project-directory ${lib.escapeShellArg spec.target} ${composeFiles} up -d --remove-orphans ${
          lib.optionalString (spec.buildBeforeUp or false) "--build"
        }
        ${lib.optionalString (healthCheck != "") ''
          healthy=0
          for _ in $(seq 1 ${toString healthRetries}); do
            if ${healthCheck}; then
              healthy=1
              break
            fi
            sleep ${toString healthInterval}
          done
          if [ "$healthy" != 1 ]; then
            echo "Health check failed for ${spec.name}: ${healthCheck}"
            nerdctl compose --project-name ${lib.escapeShellArg spec.project} --project-directory ${lib.escapeShellArg spec.target} ${composeFiles} ps || true
            exit 1
          fi
        ''}
        ${spec.postCompose}
      '';
    };
in
{
  options.lefine.containers.enable = mkEnableOption "Lefine container stacks";
  options.lefine.containers.disabledStacks = mkOption {
    type = types.listOf types.str;
    default = [ ];
    description = "Lefine compose stack names to omit on this host.";
  };
  options.lefine.containers.maddyWebmail = {
    primaryDomain = mkOption {
      type = types.str;
      default = "lefine.pro";
      description = "Mailbox domain served by Maddy.";
    };
    mailHostname = mkOption {
      type = types.str;
      default = "mail.lefine.pro";
      description = "Public MX/SMTP/IMAP hostname.";
    };
    webmailHostname = mkOption {
      type = types.str;
      default = "webmail.lefine.pro";
      description = "Public Roundcube hostname.";
    };
    leadMailbox = mkOption {
      type = types.str;
      default = "demo@lefine.pro";
      description = "Internal mailbox that receives demo leads.";
    };
    roundcubeListen = mkOption {
      type = types.str;
      default = "127.0.0.1:8082";
      description = "Host listen address for the internal Roundcube nginx proxy.";
    };
    publicIpv4 = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional public IPv4 written to the generated mail env.";
    };
  };
  options.lefine.containers.legggitLanding = {
    sourceRepo = mkOption {
      type = types.str;
      default = "https://codeberg.org/kogeletey/legggit-landing.git";
      description = "Git repository used to build the Legggit landing container.";
    };
    sourceBranch = mkOption {
      type = types.str;
      default = "main";
      description = "Git branch used to build the Legggit landing container.";
    };
    siteUrl = mkOption {
      type = types.str;
      default = "https://legggit.ru";
      description = "Public site URL passed to the Legggit landing app.";
    };
    smtpEnvFile = mkOption {
      type = types.str;
      default = "/opt/maddy-webmail/data/legggit-landing-smtp.env";
      description = "Environment file with SMTP settings for the landing app.";
    };
    port = mkOption {
      type = types.str;
      default = "3000";
      description = "Host-local port exposed by the Legggit landing container.";
    };
    fallbackSmtpHost = mkOption {
      type = types.str;
      default = "mail.lefine.pro";
      description = "SMTP host written if the generated SMTP env file is missing.";
    };
    fallbackSmtpUser = mkOption {
      type = types.str;
      default = "order@lefine.pro";
      description = "SMTP user written if the generated SMTP env file is missing.";
    };
    fallbackLeadMailbox = mkOption {
      type = types.str;
      default = "order@lefine.pro";
      description = "Lead mailbox written if the generated SMTP env file is missing.";
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /var/lib/sireng 0755 root root -"
    ]
    ++ map (spec: "d ${spec.target} 0755 root root -") composeSpecs;

    systemd.services = {
      lefine-buildkit = {
        description = "BuildKit daemon for nerdctl image builds";
        wantedBy = [ "multi-user.target" ];
        after = [ "containerd.service" ];
        requires = [ "containerd.service" ];
        serviceConfig = {
          ExecStart = "${pkgs.buildkit}/bin/buildkitd --addr unix:///run/buildkit/buildkitd.sock";
          Restart = "always";
          RuntimeDirectory = "buildkit";
        };
      };

      lefine-container-networks = {
        description = "Create Lefine container networks";
        wantedBy = [ "multi-user.target" ];
        after = [ "containerd.service" ];
        requires = [ "containerd.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [
          pkgs.coreutils
          pkgs.iptables
          pkgs.nerdctl
        ];
        script = ''
          nerdctl network inspect lefine-net >/dev/null 2>&1 || nerdctl network create lefine-net
          nerdctl network inspect source-forgejo_default >/dev/null 2>&1 || nerdctl network create source-forgejo_default
        '';
      };

      lefine-container-gc = {
        description = "Prune unused Lefine container images and build cache";
        serviceConfig = {
          Type = "oneshot";
        };
        path = [
          pkgs.buildkit
          pkgs.coreutils
          pkgs.nerdctl
        ];
        script = ''
          nerdctl system prune -f || true
          nerdctl builder prune -f || true
        '';
      };
    }
    // builtins.listToAttrs (
      map (spec: {
        name = "lefine-compose-${spec.name}";
        value = composeService spec;
      }) composeSpecs
    );

    systemd.timers.lefine-container-gc = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
  };
}
