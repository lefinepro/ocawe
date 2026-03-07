FROM crystallang/crystal:1.13.3

WORKDIR /cogni

COPY shard.yml shard.lock ./
RUN shards install

COPY . .
RUN mkdir -p /cogni/src/workflows/solver
RUN mkdir -p build && crystal build src/cli/main.cr --release -o build/cogni

EXPOSE 4111

CMD ["./build/cogni", "up", "--port", "4111", "--config-rcl", "/cogni/cogni.config.rcl"]
