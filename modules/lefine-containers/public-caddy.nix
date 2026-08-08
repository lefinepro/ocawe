{
  lib,
  pkgs,
  containersCfg ? null,
  ...
}:

let
  frontendPublicHosts = [
    "lefine.pro"
    "akash.lefine.pro"
  ];
  frontendPrimaryHost = lib.head frontendPublicHosts;
  frontendHostHeader = frontendPrimaryHost;
  frontendHostAliases = lib.concatStringsSep ", " frontendPublicHosts;
  publicCaddyfile = pkgs.writeText "public-caddy-Caddyfile" ''
    {
      storage file_system {
        root /data/caddy
      }
      default_bind 0.0.0.0
      servers {
        protocols h1
      }
    }

    monitor.lefine.pro {
      bind 0.0.0.0

      header Alt-Svc "clear"

      reverse_proxy http://10.4.1.1:3001
    }

    source.lefine.pro {
      bind 0.0.0.0

      reverse_proxy source-forgejo-caddy:80 {
        lb_try_duration 10s
        lb_try_interval 250ms
      }
    }

    fed.lefine.pro {
      bind 0.0.0.0

      reverse_proxy __FRONTEND_UPSTREAM__ {
        lb_try_duration 10s
        lb_try_interval 250ms
      }
    }

    ${frontendHostAliases} {
      bind 0.0.0.0

      handle /ocawe/webhook {
        rewrite * /v1/webhooks/cawfile
        reverse_proxy 10.4.1.1:4123
      }

      @orator_webfinger {
        path /.well-known/webfinger
        query resource=acct:orator@${frontendPrimaryHost}
      }

      handle @orator_webfinger {
        reverse_proxy __FMATCH_UPSTREAM__ {
          lb_try_duration 10s
          lb_try_interval 250ms
        }
      }

      handle /actor/orator/inbox* {
        rewrite * /inbox/orator
        reverse_proxy __FMATCH_UPSTREAM__ {
          lb_try_duration 10s
          lb_try_interval 250ms
        }
      }

      handle /actor/orator/outbox* {
        rewrite * /outbox/orator
        reverse_proxy __FMATCH_UPSTREAM__ {
          lb_try_duration 10s
          lb_try_interval 250ms
        }
      }

      handle /actor/orator* {
        reverse_proxy __FMATCH_UPSTREAM__ {
          lb_try_duration 10s
          lb_try_interval 250ms
        }
      }

      handle /actors/orator/inbox* {
        rewrite * /inbox/orator
        reverse_proxy __FMATCH_UPSTREAM__ {
          lb_try_duration 10s
          lb_try_interval 250ms
        }
      }

      handle /actors/orator/outbox* {
        rewrite * /outbox/orator
        reverse_proxy __FMATCH_UPSTREAM__ {
          lb_try_duration 10s
          lb_try_interval 250ms
        }
      }

      handle /actors/orator* {
        reverse_proxy __FMATCH_UPSTREAM__ {
          lb_try_duration 10s
          lb_try_interval 250ms
        }
      }

      handle /.well-known/webfinger {
        reverse_proxy __ORATOR_UPSTREAM__ {
          lb_try_duration 10s
          lb_try_interval 250ms
        }
      }

      handle /actors/* {
        reverse_proxy __ORATOR_UPSTREAM__ {
          lb_try_duration 10s
          lb_try_interval 250ms
        }
      }

      handle /inbox {
        reverse_proxy __ORATOR_UPSTREAM__ {
          lb_try_duration 10s
          lb_try_interval 250ms
        }
      }

      handle /v1/* {
        reverse_proxy __ORATOR_UPSTREAM__ {
          lb_try_duration 10s
          lb_try_interval 250ms
        }
      }

      handle_path /openai/* {
        reverse_proxy __ORATOR_UPSTREAM__ {
          lb_try_duration 10s
          lb_try_interval 250ms
        }
      }

      handle_path /api/openai/* {
        reverse_proxy __ORATOR_UPSTREAM__ {
          lb_try_duration 10s
          lb_try_interval 250ms
        }
      }

      handle {
        reverse_proxy __FRONTEND_UPSTREAM__ {
          lb_try_duration 10s
          lb_try_interval 250ms
        }
      }
    }
  '';

  publicCompose = pkgs.writeText "public-caddy-compose.yml" ''
    services:
      public-caddy:
        image: caddy:2.8-alpine
        container_name: public-caddy
        restart: unless-stopped
        volumes:
          - ./Caddyfile:/etc/caddy/Caddyfile:ro
          - ./data:/data
          - ./config:/config
        ports:
          - "0.0.0.0:80:80"
          - "0.0.0.0:443:443"
        networks:
          - lefine-net

    networks:
      lefine-net:
        external: true
        name: lefine-net
  '';
in
{
  name = "public-caddy";
  target = "/opt/public-caddy";
  compose = "${publicCompose}";
  project = "public-caddy";
  afterCompose = [
    "orator"
    "frontend"
  ];
  extraCompose = "";
  healthCheck = "nerdctl ps --filter name=public-caddy --format '{{.Status}}' | awk '$0 == \"Up\" { ok = 1 } END { exit ok ? 0 : 1 }' && curl -4fsS --max-time 20 https://lefine.pro/v1/models | grep -q 'acct:orator@lefine.pro'";
  healthRetries = 30;
  healthInterval = 2;
  extraPath = [
    pkgs.caddy
    pkgs.iproute2
  ];
  preCompose = ''
    nerdctl rm -f public-caddy 2>/dev/null || true
    for stale_pid in $(ss -H -ltnp '( sport = :80 or sport = :443 )' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u); do
      if [ -e "/proc/$stale_pid/root/etc/caddy/Caddyfile" ] \
        && grep -q 'monitor\.lefine\.pro\|lefine\.pro' "/proc/$stale_pid/root/etc/caddy/Caddyfile"; then
        stale_scope="$(sed -n 's|0::/system.slice/\(nerdctl-[^.]*\.scope\).*|\1|p' "/proc/$stale_pid/cgroup" | head -n1)"
        if [ -n "$stale_scope" ]; then
          /run/current-system/sw/bin/systemctl stop "$stale_scope" || true
        else
          kill "$stale_pid" || true
        fi
      fi
    done
    while stale_rule="$(iptables -t nat -L CNI-HOSTPORT-DNAT --line-numbers 2>/dev/null | awk '/dports 80,443/ { print $1; exit }')" \
      && [ -n "$stale_rule" ]; do
      iptables -t nat -D CNI-HOSTPORT-DNAT "$stale_rule"
    done
    cp ${publicCaddyfile} /opt/public-caddy/Caddyfile
    frontend_upstream="frontend:3000"
    sed -i "s|__FRONTEND_UPSTREAM__|$frontend_upstream|g" /opt/public-caddy/Caddyfile
    orator_upstream="orator-app:8080"
    sed -i "s|__ORATOR_UPSTREAM__|$orator_upstream|g" /opt/public-caddy/Caddyfile
    fmatch_upstream="fmatch:7277"
    sed -i "s|__FMATCH_UPSTREAM__|$fmatch_upstream|g" /opt/public-caddy/Caddyfile
  '';
  postCompose = "";
}
