FROM crystallang/crystal:1.13.3

WORKDIR /cogni

RUN apt-get update \
  && apt-get install -y --no-install-recommends libsqlite3-dev nodejs npm ruby \
  && rm -rf /var/lib/apt/lists/*

COPY shard.yml shard.lock ./
RUN shards update

COPY . .
RUN shards build cogni --release --no-debug
RUN chmod +x /cogni/entrypoint.sh

EXPOSE 4111

ENTRYPOINT ["bash", "/cogni/entrypoint.sh"]
