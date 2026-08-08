{ ... }:

{
  name = "source-forgejo";
  target = "/opt/source-forgejo";
  compose = "/opt/source-forgejo/docker-compose.yml";
  project = "source-forgejo";
  requiresExistingCompose = false;
  afterCompose = [ ];
  extraCompose = "";
  preCompose = ''
    source_postgres_password_file="/opt/source-forgejo/.postgres-password"
    source_postgres_password="$(awk -F': ' '/POSTGRES_PASSWORD:/ { print $2; exit }' /opt/source-forgejo/docker-compose.yml 2>/dev/null || true)"
    source_postgres_password="''${source_postgres_password%\"}"
    source_postgres_password="''${source_postgres_password#\"}"
    if [ -z "$source_postgres_password" ] && [ -f "$source_postgres_password_file" ]; then
      source_postgres_password="$(cat "$source_postgres_password_file")"
    fi
    if [ -z "$source_postgres_password" ]; then
      source_postgres_password="$(openssl rand -base64 32)"
    fi
    printf '%s\n' "$source_postgres_password" > "$source_postgres_password_file"
    chmod 600 "$source_postgres_password_file"

    tmp_compose="$(mktemp)"
    cat > "$tmp_compose" <<EOF
    services:
      postgres:
        image: postgres:18-alpine
        restart: unless-stopped
        environment:
          POSTGRES_DB: forgejo
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: "$source_postgres_password"
          POSTGRES_INITDB_ARGS: --encoding UTF-8 --locale C
          PGDATA: /var/lib/postgresql/18/docker
        volumes:
          - ./volumes/postgres:/var/lib/postgresql
        healthcheck:
          test: ["CMD-SHELL", "pg_isready -U postgres -d forgejo"]
          interval: 10s
          timeout: 5s
          retries: 20

      forgejo:
        image: codeberg.org/forgejo/forgejo:15
        restart: unless-stopped
        depends_on:
          postgres:
            condition: service_healthy
        environment:
          USER_UID: 1000
          USER_GID: 1000
          FORGEJO__database__DB_TYPE: postgres
          FORGEJO__database__HOST: postgres:5432
          FORGEJO__database__NAME: forgejo
          FORGEJO__database__USER: postgres
          FORGEJO__database__PASSWD: "$source_postgres_password"
          FORGEJO__server__ROOT_URL: https://source.lefine.pro/
          FORGEJO__server__DOMAIN: source.lefine.pro
          FORGEJO__server__SSH_DOMAIN: source.lefine.pro
          FORGEJO__server__START_SSH_SERVER: "false"
          FORGEJO__server__DISABLE_SSH: "false"
          FORGEJO__server__SSH_PORT: "2222"
        volumes:
          - ./volumes/forgejo:/data
          - /etc/timezone:/etc/timezone:ro
          - /etc/localtime:/etc/localtime:ro
        ports:
          - "2222:22"
        expose:
          - "3000"

      caddy:
        image: caddy:2.8-alpine
        restart: unless-stopped
        depends_on:
          - forgejo
        ports:
          - "127.0.0.1:8080:80"
          - "127.0.0.1:8443:443"
        volumes:
          - ./Caddyfile:/etc/caddy/Caddyfile:ro
          - ./volumes/caddy/data:/data
          - ./volumes/caddy/config:/config
        networks:
          default:
          lefine-net:
            aliases:
              - source-forgejo-caddy

    volumes: {}

    networks:
      default:
        name: source-forgejo_default
      lefine-net:
        external: true
        name: lefine-net
    EOF
    mv "$tmp_compose" /opt/source-forgejo/docker-compose.yml
    cat > /opt/source-forgejo/Caddyfile <<EOF
    :80 {
      reverse_proxy forgejo:3000
    }
    EOF
    nerdctl network rm source-forgejo_default >/dev/null 2>&1 || true
    mkdir -p /opt/source-forgejo/volumes/forgejo
    chown -R 1000:1000 /opt/source-forgejo/volumes/forgejo
    chmod -R u+rwX /opt/source-forgejo/volumes/forgejo
    rm -f /opt/source-forgejo/volumes/forgejo/git/.ssh/authorized_keys
  '';
  postCompose = "";
}
