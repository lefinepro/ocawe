FROM crystallang/crystal:1.13.3

WORKDIR /ocawe

RUN apt-get update \
  && apt-get install -y --no-install-recommends libsqlite3-dev nodejs npm ruby \
  && rm -rf /var/lib/apt/lists/*

COPY shard.yml shard.lock ./
RUN shards update --production

COPY . .
RUN shards build ocawe --release --no-debug
RUN chmod +x /ocawe/entrypoint.sh

EXPOSE 4111

ENTRYPOINT ["bash", "/ocawe/entrypoint.sh"]
