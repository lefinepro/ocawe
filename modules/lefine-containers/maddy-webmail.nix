{
  pkgs,
  containersCfg ? null,
  ...
}:

let
  cfg = if containersCfg == null then { } else (containersCfg.maddyWebmail or { });

  primaryDomain = cfg.primaryDomain or "lefine.pro";
  mailHostname = cfg.mailHostname or "mail.lefine.pro";
  webmailHostname = cfg.webmailHostname or "webmail.lefine.pro";
  leadMailbox = cfg.leadMailbox or "demo@lefine.pro";
  roundcubeListen = cfg.roundcubeListen or "127.0.0.1:8082";
  publicIpv4 = if cfg.publicIpv4 or null == null then "" else cfg.publicIpv4;
  certDir = "/opt/maddy-webmail/certs/${mailHostname}";

  roundcubeNginxConf = pkgs.writeText "roundcube-nginx.conf" ''
    server {
        listen 80;
        server_name _;

        root /var/www/html/public_html;
        index index.php;

        client_max_body_size 25m;

        location / {
            try_files $uri $uri/ /index.php?$query_string;
        }

        location ~ ^(.+\.php)(/.*)?$ {
            include /etc/nginx/fastcgi_params;
            fastcgi_split_path_info ^(.+\.php)(/.*)$;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            fastcgi_param SCRIPT_NAME $fastcgi_script_name;
            fastcgi_param PATH_INFO $fastcgi_path_info;
            fastcgi_param HTTPS on;
            fastcgi_pass roundcube:9000;
        }

        location ~* \.(?:css|js|jpg|jpeg|gif|png|ico|svg|webp|woff2?)$ {
            expires 1d;
            add_header Cache-Control "public";
            try_files $uri /index.php?$query_string;
        }
    }
  '';

  roundcubeConfig = pkgs.writeText "roundcube-config.inc.php.template" ''
    <?php
    $config['plugins'] = [];
    $config['log_driver'] = 'stdout';
    $config['zipdownload_selection'] = true;
    $config['des_key'] = getenv('ROUNDCUBE_DES_KEY') ?: 'replace-me';
    $config['enable_spellcheck'] = true;
    $config['spellcheck_engine'] = 'pspell';
    include(__DIR__ . '/config.docker.inc.php');

    $config['imap_conn_options'] = [
        'ssl' => [
            'verify_peer' => false,
            'verify_peer_name' => false,
            'allow_self_signed' => true,
        ],
    ];
    $config['smtp_conn_options'] = [
        'ssl' => [
            'verify_peer' => false,
            'verify_peer_name' => false,
            'allow_self_signed' => true,
        ],
    ];
  '';

  maddyEntrypoint = pkgs.writeText "maddy-entrypoint.sh" ''
    #!/bin/sh
    set -eu

    CONFIG_DIR="''${MADDY_CONFIG_DIR:-/etc/maddy}"
    STATE_DIR="''${MADDY_STATE_DIR:-/var/lib/maddy}"
    RUN_DIR="''${MADDY_RUN_DIR:-/run/maddy}"
    DOMAINS="''${DOMAINS:-}"
    PRIMARY_DOMAIN="''${PRIMARY_DOMAIN:-}"
    MX_HOSTNAME="''${MX_HOSTNAME:-}"

    if [ -z "$DOMAINS" ]; then
      echo "DOMAINS is required" >&2
      exit 1
    fi

    if [ -z "$PRIMARY_DOMAIN" ]; then
      set -- $DOMAINS
      PRIMARY_DOMAIN="''${1:-}"
    fi

    if [ -z "$PRIMARY_DOMAIN" ]; then
      echo "PRIMARY_DOMAIN could not be determined" >&2
      exit 1
    fi

    if [ -z "$MX_HOSTNAME" ]; then
      MX_HOSTNAME="mail.''${PRIMARY_DOMAIN}"
    fi

    REWRITE_LINE='    optional_step regexp "(.+)\\+(.+)@(.+)" "$1@$3"'

    mkdir -p "$CONFIG_DIR" "$STATE_DIR" "$RUN_DIR" "$CONFIG_DIR/certs/$MX_HOSTNAME"
    touch "$CONFIG_DIR/aliases"

    if [ ! -s "$CONFIG_DIR/certs/$MX_HOSTNAME/fullchain.pem" ] || [ ! -s "$CONFIG_DIR/certs/$MX_HOSTNAME/privkey.pem" ]; then
      openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -keyout "$CONFIG_DIR/certs/$MX_HOSTNAME/privkey.pem" \
        -out "$CONFIG_DIR/certs/$MX_HOSTNAME/fullchain.pem" \
        -subj "/CN=$MX_HOSTNAME" >/dev/null 2>&1
    fi

    cat > "$CONFIG_DIR/maddy.conf" <<EOF
    state_dir $STATE_DIR
    runtime_dir $RUN_DIR

    \$(hostname) = $MX_HOSTNAME
    \$(primary_domain) = $PRIMARY_DOMAIN
    \$(local_domains) = $DOMAINS

    tls file $CONFIG_DIR/certs/$MX_HOSTNAME/fullchain.pem $CONFIG_DIR/certs/$MX_HOSTNAME/privkey.pem

    auth.pass_table local_authdb {
        table sql_table {
            driver sqlite3
            dsn $STATE_DIR/credentials.db
            table_name passwords
        }
    }

    storage.imapsql local_mailboxes {
        driver sqlite3
        dsn $STATE_DIR/imapsql.db
    }

    table.chain local_rewrites {
    $(printf '%s\n' "$REWRITE_LINE")
        optional_step static {
            entry postmaster postmaster@\$(primary_domain)
        }
        optional_step file $CONFIG_DIR/aliases
    }

    msgpipeline local_routing {
        hostname $MX_HOSTNAME
        destination postmaster \$(local_domains) {
            modify {
                replace_rcpt &local_rewrites
            }
            deliver_to &local_mailboxes
        }
        default_destination {
            reject 550 5.1.1 "User doesn't exist"
        }
    }

    smtp tcp://0.0.0.0:25 {
        hostname $MX_HOSTNAME
        limits {
            all rate 20 1s
            all concurrency 10
        }
        dmarc yes
        check {
            require_mx_record
            dkim
            spf
        }
        source \$(local_domains) {
            reject 501 5.1.8 "Use Submission for outgoing SMTP"
        }
        default_source {
            destination postmaster \$(local_domains) {
                deliver_to &local_routing
            }
            default_destination {
                reject 550 5.1.1 "User doesn't exist"
            }
        }
    }

    target.remote outbound_delivery {
        hostname $MX_HOSTNAME
        limits {
            destination rate 20 1s
            destination concurrency 10
        }
    }

    target.queue remote_queue {
        hostname $MX_HOSTNAME
        target &outbound_delivery
        autogenerated_msg_domain \$(primary_domain)
        bounce {
            destination postmaster \$(local_domains) {
                deliver_to &local_routing
            }
            default_destination {
                reject 550 5.0.0 "Refusing to send DSNs to non-local addresses"
            }
        }
    }

    submission tls://0.0.0.0:465 tcp://0.0.0.0:587 {
        hostname $MX_HOSTNAME
        limits {
            all rate 50 1s
        }
        auth &local_authdb
        source \$(local_domains) {
            check {
                authorize_sender {
                    prepare_email &local_rewrites
                    user_to_email identity
                }
            }
            destination postmaster \$(local_domains) {
                deliver_to &local_routing
            }
            default_destination {
                modify {
                    dkim \$(primary_domain) \$(local_domains) default
                }
                deliver_to &remote_queue
            }
        }
        default_source {
            reject 501 5.1.8 "Non-local sender domain"
        }
    }

    imap tls://0.0.0.0:993 tcp://0.0.0.0:143 {
        auth &local_authdb
        storage &local_mailboxes
    }
    EOF

    exec /usr/local/bin/maddy --config "$CONFIG_DIR/maddy.conf" run
  '';

  syncSource = pkgs.writeText "maddy_csv_sync.cr" ''
    require "csv"
    require "option_parser"
    require "set"

    record Account, login : String, password : String

    class Config
      property csv_path : String
      property maddy_bin : String
      property maddy_config : String?
      property maddy_user : String
      property default_domain : String?
      property dry_run : Bool

      def initialize
        @csv_path = "/etc/cogni/mail_passwords.csv"
        @maddy_bin = "/usr/local/bin/maddy"
        @maddy_config = nil
        @maddy_user = ""
        @default_domain = nil
        @dry_run = false
      end
    end

    class Summary
      property total : Int32
      property mailboxes_created : Int32
      property mailboxes_existing : Int32
      property credentials_created : Int32
      property credentials_updated : Int32

      def initialize
        @total = 0
        @mailboxes_created = 0
        @mailboxes_existing = 0
        @credentials_created = 0
        @credentials_updated = 0
      end
    end

    class CsvSync
      def initialize(@config : Config)
      end

      def run : Summary
        accounts = load_accounts
        mailbox_set = list_set("imap-acct", "list")
        credential_set = list_set("creds", "list")
        summary = Summary.new

        accounts.each do |account|
          summary.total += 1

          if ensure_mailbox(account, mailbox_set)
            summary.mailboxes_created += 1
          else
            summary.mailboxes_existing += 1
          end

          if ensure_credential(account, credential_set)
            summary.credentials_created += 1
          else
            summary.credentials_updated += 1
          end
        end

        summary
      end

      private def load_accounts : Array(Account)
        accounts = [] of Account

        File.open(@config.csv_path) do |file|
          csv = CSV.new(file, headers: true, strip: true)

          while csv.next
            values = csv.row.to_h
            login = first_field(values, %w[email login username user])
            password = first_field(values, %w[password pass secret])
            next if login.empty? || password.empty?

            normalized = normalize_login(login)
            raise ArgumentError.new("login is empty in #{@config.csv_path}") if normalized.empty?

            accounts << Account.new(normalized, password)
          end
        end

        accounts.sort_by(&.login)
      end

      private def normalize_login(raw_login : String) : String
        login = raw_login.strip.downcase
        return login if login.includes?("@")

        default_domain = @config.default_domain
        if default_domain.nil? || default_domain.strip.empty?
          raise ArgumentError.new("login #{login.inspect} has no domain; pass --domain <domain> or use a full email address")
        end

        "#{login}@#{default_domain.strip.downcase}"
      end

      private def first_field(values : Hash(String, String), names : Array(String)) : String
        values.each do |key, value|
          return value.strip if names.includes?(key.downcase)
        end
        ""
      end

      private def list_set(*args : String) : Set(String)
        output = run_maddy(*args)
        set = Set(String).new

        output.each_line do |line|
          value = line.strip.downcase
          set << value unless value.empty?
        end

        set
      end

      private def ensure_mailbox(account : Account, mailbox_set : Set(String)) : Bool
        return false if mailbox_set.includes?(account.login)

        run_maddy("imap-acct", "create", account.login) unless @config.dry_run
        mailbox_set << account.login
        true
      end

      private def ensure_credential(account : Account, credential_set : Set(String)) : Bool
        if credential_set.includes?(account.login)
          run_maddy("creds", "password", account.login, input: "#{account.password}\n") unless @config.dry_run
          return false
        end

        run_maddy("creds", "create", account.login, input: "#{account.password}\n#{account.password}\n") unless @config.dry_run
        credential_set << account.login
        true
      end

      private def run_maddy(*args : String, input : String? = nil) : String
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        stdin = input ? IO::Memory.new(input) : IO::Memory.new
        cli_args = [] of String
        if config_path = @config.maddy_config
          cli_args << "--config" << config_path
        end
        cli_args.concat(args.to_a)

        status = if @config.maddy_user.strip.empty? || @config.maddy_user == "root"
          Process.run(@config.maddy_bin, cli_args, input: stdin, output: stdout, error: stderr)
        else
          command = ["-u", @config.maddy_user, "--", @config.maddy_bin] + cli_args
          Process.run("runuser", command, input: stdin, output: stdout, error: stderr)
        end

        return stdout.to_s if status.success?

        message = stderr.to_s.strip
        message = stdout.to_s.strip if message.empty?
        raise RuntimeError.new("maddy #{args.join(" ")} failed: #{message}")
      end
    end

    def build_config : Config
      config = Config.new

      OptionParser.parse do |parser|
        parser.banner = "Usage: maddy-csv-sync [options]"
        parser.on("--csv PATH", "CSV file with login,password columns") { |value| config.csv_path = value }
        parser.on("--maddy-bin PATH", "Path to maddy CLI") { |value| config.maddy_bin = value }
        parser.on("--maddy-config PATH", "Path to maddy config") { |value| config.maddy_config = value }
        parser.on("--maddy-user USER", "User to run maddy as") { |value| config.maddy_user = value }
        parser.on("--domain DOMAIN", "Fallback domain for logins without @") { |value| config.default_domain = value }
        parser.on("--dry-run", "Show planned actions without changing Maddy") { config.dry_run = true }
        parser.on("-h", "--help", "Show help") do
          puts parser
          exit 0
        end
      end

      config
    end

    begin
      config = build_config
      summary = CsvSync.new(config).run

      puts "synced #{summary.total} accounts"
      puts "mailboxes: #{summary.mailboxes_created} created, #{summary.mailboxes_existing} existing"
      puts "credentials: #{summary.credentials_created} created, #{summary.credentials_updated} updated"
    rescue ex : Exception
      STDERR.puts ex.message
      exit 1
    end
  '';

  maddyDockerfile = pkgs.writeText "maddy.Dockerfile" ''
    FROM alpine:3.22

    ARG MADDY_VERSION=0.8.2

    RUN apk add --no-cache ca-certificates curl openssl tzdata zstd

    RUN set -eux; \
        curl -fsSL -o /tmp/maddy.tar.zst "https://github.com/foxcpp/maddy/releases/download/v''${MADDY_VERSION}/maddy-''${MADDY_VERSION}-x86_64-linux-musl.tar.zst"; \
        unzstd -c /tmp/maddy.tar.zst | tar -C /tmp -xf -; \
        maddy_bin="$(find /tmp -maxdepth 3 -type f -name maddy | head -n 1)"; \
        install -m 0755 "$maddy_bin" /usr/local/bin/maddy; \
        rm -rf /tmp/maddy.tar.zst /tmp/maddy-*

    COPY maddy/entrypoint.sh /usr/local/bin/maddy-entrypoint
    RUN chmod +x /usr/local/bin/maddy-entrypoint

    VOLUME ["/etc/maddy", "/var/lib/maddy"]

    EXPOSE 25 465 587 143 993

    ENTRYPOINT ["/usr/local/bin/maddy-entrypoint"]
  '';

  syncDockerfile = pkgs.writeText "maddy-csv-sync.Dockerfile" ''
    FROM crystallang/crystal:1.19.1-alpine

    RUN apk add --no-cache ca-certificates curl tzdata zstd

    WORKDIR /app

    COPY crystal-sync/shard.yml /app/shard.yml
    COPY crystal-sync/src /app/src

    RUN crystal build src/maddy_csv_sync.cr -o /usr/local/bin/maddy-csv-sync --release

    ARG MADDY_VERSION=0.8.2
    RUN set -eux; \
        curl -fsSL -o /tmp/maddy.tar.zst "https://github.com/foxcpp/maddy/releases/download/v''${MADDY_VERSION}/maddy-''${MADDY_VERSION}-x86_64-linux-musl.tar.zst"; \
        unzstd -c /tmp/maddy.tar.zst | tar -C /tmp -xf -; \
        maddy_bin="$(find /tmp -maxdepth 3 -type f -name maddy | head -n 1)"; \
        install -m 0755 "$maddy_bin" /usr/local/bin/maddy; \
        rm -rf /tmp/maddy.tar.zst /tmp/maddy-*

    ENTRYPOINT ["/usr/local/bin/maddy-csv-sync"]
    CMD ["--csv", "/etc/cogni/mail_passwords.csv", "--maddy-config", "/etc/maddy/maddy.conf"]
  '';

  syncShard = pkgs.writeText "shard.yml" ''
    name: maddy_csv_sync
    version: 0.1.0
    targets:
      maddy_csv_sync:
        main: src/maddy_csv_sync.cr
    crystal: ">= 1.19.0"
  '';

  maddyWebmailCompose = pkgs.writeText "maddy-webmail-compose.yml" ''
    services:
      maddy:
        image: maddy-mail:latest
        container_name: maddy-mail
        restart: unless-stopped
        environment:
          DOMAINS: "${primaryDomain}"
          PRIMARY_DOMAIN: "${primaryDomain}"
          MX_HOSTNAME: "${mailHostname}"
          MAIL_SERVER_IP: "${publicIpv4}"
        volumes:
          - maddy-config:/etc/maddy
          - maddy-data:/var/lib/maddy
          - ${certDir}/${mailHostname}.crt:/etc/maddy/certs/${mailHostname}/fullchain.pem:ro
          - ${certDir}/${mailHostname}.key:/etc/maddy/certs/${mailHostname}/privkey.pem:ro
        network_mode: host
        read_only: true
        tmpfs:
          - /run/maddy:size=16M
          - /tmp:size=64M

      maddy-csv-sync:
        image: maddy-csv-sync:latest
        container_name: maddy-csv-sync
        restart: "no"
        depends_on:
          - maddy
        volumes:
          - ''${MADDY_PASSWORDS_CSV:-./data/mail_passwords_lefine.csv}:/etc/cogni/mail_passwords.csv:ro
          - maddy-config:/etc/maddy:ro
          - maddy-data:/var/lib/maddy
        read_only: true
        tmpfs:
          - /run/maddy:size=16M
          - /tmp:size=64M

      roundcube:
        image: roundcube/roundcubemail:latest-fpm-alpine
        restart: unless-stopped
        environment:
          ROUNDCUBEMAIL_DEFAULT_HOST: "ssl://${mailHostname}"
          ROUNDCUBEMAIL_DEFAULT_PORT: "993"
          ROUNDCUBEMAIL_SMTP_SERVER: "tls://${mailHostname}"
          ROUNDCUBEMAIL_SMTP_PORT: "587"
          ROUNDCUBEMAIL_SKIN: "elastic"
          ROUNDCUBE_DES_KEY: "''${ROUNDCUBE_DES_KEY}"
        volumes:
          - ./volumes/roundcube/html:/var/www/html
          - ./volumes/roundcube/data:/var/roundcube
          - ./roundcube-config.inc.php:/var/www/html/config/config.inc.php:ro
          - ${certDir}/${mailHostname}.crt:/etc/roundcube-certs/${mailHostname}.pem:ro

      roundcube-nginx:
        image: nginx:alpine
        restart: unless-stopped
        depends_on:
          - roundcube
        ports:
          - "${roundcubeListen}:80"
        volumes:
          - ./roundcube/nginx.conf:/etc/nginx/conf.d/default.conf:ro
          - ./volumes/roundcube/html:/var/www/html:ro
        networks:
          default:
          lefine-net:
            aliases:
              - roundcube-nginx

    volumes:
      maddy-config:
        name: maddy-webmail_maddy-config
      maddy-data:
        name: maddy-webmail_maddy-data

    networks:
      lefine-net:
        external: true
        name: lefine-net
  '';
in
{
  name = "maddy-webmail";
  target = "/opt/maddy-webmail";
  compose = "/opt/maddy-webmail/docker-compose.yml";
  project = "maddy-webmail";
  requiresExistingCompose = false;
  afterCompose = [ ];
  extraCompose = "";
  preCompose = ''
    mkdir -p /opt/maddy-webmail/data
    mkdir -p /opt/maddy-webmail/scripts
    mkdir -p /opt/maddy-webmail/roundcube
    mkdir -p /opt/maddy-webmail/volumes/roundcube
    mkdir -p /opt/maddy-webmail/maddy
    mkdir -p /opt/maddy-webmail/crystal-sync/src
    mkdir -p ${certDir}

    if [ -e /var/lib/nerdctl/1935db59/names/default/maddy-mail ] \
      && ! nerdctl container inspect maddy-mail >/dev/null 2>&1; then
      rm -f /var/lib/nerdctl/1935db59/names/default/maddy-mail
    fi

    mail_cert="${certDir}/${mailHostname}.crt"
    mail_key="${certDir}/${mailHostname}.key"
    for caddy_cert_dir in \
      "/opt/public-caddy/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${mailHostname}" \
      "/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${mailHostname}"
    do
      if [ -s "$caddy_cert_dir/${mailHostname}.crt" ] && [ -s "$caddy_cert_dir/${mailHostname}.key" ]; then
        cp "$caddy_cert_dir/${mailHostname}.crt" "$mail_cert"
        cp "$caddy_cert_dir/${mailHostname}.key" "$mail_key"
        chmod 600 "$mail_key"
        chmod 644 "$mail_cert"
        break
      fi
    done
    if [ -d "$mail_cert" ]; then
      rm -rf "$mail_cert"
    fi
    if [ -d "$mail_key" ]; then
      rm -rf "$mail_key"
    fi
    if [ ! -s "$mail_cert" ] || [ ! -s "$mail_key" ]; then
      openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$mail_key" \
        -out "$mail_cert" \
        -days 30 \
        -subj "/CN=${mailHostname}" >/dev/null 2>&1
      chmod 600 "$mail_key"
      chmod 644 "$mail_cert"
    fi

    maddy_config_volume="$(nerdctl volume inspect maddy-webmail_maddy-config 2>/dev/null | jq -r '.[0].Mountpoint // empty' || true)"
    if [ -n "$maddy_config_volume" ] && [ -d "$maddy_config_volume/certs/${mailHostname}" ]; then
      if [ -d "$maddy_config_volume/certs/${mailHostname}/fullchain.pem" ]; then
        rm -rf "$maddy_config_volume/certs/${mailHostname}/fullchain.pem"
      fi
      if [ -d "$maddy_config_volume/certs/${mailHostname}/privkey.pem" ]; then
        rm -rf "$maddy_config_volume/certs/${mailHostname}/privkey.pem"
      fi
    fi

    cp ${maddyWebmailCompose} /opt/maddy-webmail/docker-compose.yml
    cp ${roundcubeNginxConf} /opt/maddy-webmail/roundcube/nginx.conf
    cp ${roundcubeConfig} /opt/maddy-webmail/roundcube-config.inc.php
    cp ${maddyDockerfile} /opt/maddy-webmail/maddy/Dockerfile
    cp ${maddyEntrypoint} /opt/maddy-webmail/maddy/entrypoint.sh
    chmod +x /opt/maddy-webmail/maddy/entrypoint.sh
    cp ${syncDockerfile} /opt/maddy-webmail/crystal-sync/Dockerfile
    cp ${syncShard} /opt/maddy-webmail/crystal-sync/shard.yml
    cp ${syncSource} /opt/maddy-webmail/crystal-sync/src/maddy_csv_sync.cr

    cat > /opt/maddy-webmail/data/mail-server.lefine.env <<EOF
    DOMAINS="${primaryDomain}"
    PRIMARY_DOMAIN="${primaryDomain}"
    MX_HOSTNAME="${mailHostname}"
    MAIL_SERVER_IP="${publicIpv4}"
    EOF
    chmod 600 /opt/maddy-webmail/data/mail-server.lefine.env

    if [ ! -s /opt/maddy-webmail/data/lead-mailbox-password ]; then
      openssl rand -base64 24 > /opt/maddy-webmail/data/lead-mailbox-password
      chmod 600 /opt/maddy-webmail/data/lead-mailbox-password
    fi
    lead_password="$(cat /opt/maddy-webmail/data/lead-mailbox-password)"
    if [ ! -s /opt/maddy-webmail/data/mail_passwords_lefine.csv ]; then
      {
        printf 'Email,Password\n'
        printf '"%s","%s"\n' '${leadMailbox}' "$lead_password"
      } > /opt/maddy-webmail/data/mail_passwords_lefine.csv
      chmod 600 /opt/maddy-webmail/data/mail_passwords_lefine.csv
    elif ! grep -Fqi '${leadMailbox}' /opt/maddy-webmail/data/mail_passwords_lefine.csv; then
      printf '"%s","%s"\n' '${leadMailbox}' "$lead_password" >> /opt/maddy-webmail/data/mail_passwords_lefine.csv
    fi

    cat > /opt/maddy-webmail/data/legggit-landing-smtp.env <<EOF
    SMTP_HOST=${mailHostname}
    SMTP_PORT=587
    SMTP_USER=${leadMailbox}
    SMTP_PASS=$lead_password
    LEAD_TO_EMAIL=${leadMailbox}
    LEAD_FROM_EMAIL=${leadMailbox}
    EOF
    chmod 600 /opt/maddy-webmail/data/legggit-landing-smtp.env

    if [ ! -s /opt/maddy-webmail/.roundcube-des-key ]; then
      openssl rand -hex 24 > /opt/maddy-webmail/.roundcube-des-key
      chmod 600 /opt/maddy-webmail/.roundcube-des-key
    fi
    export ROUNDCUBE_DES_KEY="$(cat /opt/maddy-webmail/.roundcube-des-key)"

    if ! nerdctl image inspect maddy-mail:latest >/dev/null 2>&1; then
      nerdctl build -t maddy-mail:latest -f /opt/maddy-webmail/maddy/Dockerfile /opt/maddy-webmail
    fi

    if ! nerdctl image inspect maddy-csv-sync:latest >/dev/null 2>&1; then
      nerdctl build -t maddy-csv-sync:latest -f /opt/maddy-webmail/crystal-sync/Dockerfile /opt/maddy-webmail
    fi

    cat > /opt/maddy-webmail/scripts/sync-container.sh <<'EOF'
    #!/usr/bin/env bash
    set -euo pipefail

    cd /opt/maddy-webmail

    if [ ! -f ./data/mail-server.lefine.env ]; then
      echo "Missing ./data/mail-server.lefine.env" >&2
      exit 2
    fi

    if [ ! -f ./data/mail_passwords_lefine.csv ]; then
      echo "Missing ./data/mail_passwords_lefine.csv" >&2
      exit 2
    fi

    if ! nerdctl image inspect maddy-mail:latest >/dev/null 2>&1; then
      nerdctl build -t maddy-mail:latest -f ./maddy/Dockerfile .
    fi

    if ! nerdctl image inspect maddy-csv-sync:latest >/dev/null 2>&1; then
      nerdctl build -t maddy-csv-sync:latest -f ./crystal-sync/Dockerfile .
    fi

    export ROUNDCUBE_DES_KEY="$(cat /opt/maddy-webmail/.roundcube-des-key)"

    nerdctl compose up -d maddy
    env \
      MADDY_ENV_FILE=./data/mail-server.lefine.env \
      MADDY_PASSWORDS_CSV=./data/mail_passwords_lefine.csv \
      nerdctl compose run --rm --no-deps --interactive=false maddy-csv-sync

    for _ in $(seq 1 30); do
      if [ "$(nerdctl inspect -f "{{.State.Status}}" maddy-mail 2>/dev/null || true)" = "running" ]; then
        break
      fi
      sleep 1
    done

    if [ "$(nerdctl inspect -f "{{.State.Status}}" maddy-mail 2>/dev/null || true)" != "running" ]; then
      echo "maddy-mail is not running after compose sync; leaving container restart policy to recover." >&2
      nerdctl logs --tail 80 maddy-mail >&2 || true
      exit 0
    fi

    nerdctl exec maddy-mail sh -lc '
      echo "== creds =="
      /usr/local/bin/maddy creds list
      echo "== imap accounts =="
      /usr/local/bin/maddy imap-acct list
    '
    EOF
    sed -i 's/^    //' /opt/maddy-webmail/scripts/sync-container.sh
    chmod +x /opt/maddy-webmail/scripts/sync-container.sh

    mkdir -p /opt/maddy-webmail/volumes/roundcube/data
    chown -R 82:82 /opt/maddy-webmail/volumes/roundcube/data
    chmod -R u+rwX,g+rwX /opt/maddy-webmail/volumes/roundcube/data
  '';
  postCompose = ''
    export ROUNDCUBE_DES_KEY="$(cat /opt/maddy-webmail/.roundcube-des-key)"
    /opt/maddy-webmail/scripts/sync-container.sh
    nerdctl compose --project-name maddy-webmail --project-directory /opt/maddy-webmail -f /opt/maddy-webmail/docker-compose.yml up -d roundcube roundcube-nginx
  '';
}
