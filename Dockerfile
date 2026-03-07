FROM crystallang/crystal:1.13.3

WORKDIR /cogni

COPY shard.yml shard.lock ./
RUN shards install

COPY . .
RUN mkdir -p /cogni/src/workflows/solver
RUN shards install && shards build --release --no-debug
RUN chmod +x /cogni/entrypoint.sh

EXPOSE 4111

ENTRYPOINT ["/cogni/entrypoint.sh"]
