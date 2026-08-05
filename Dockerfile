FROM crystallang/crystal:1.19.1

WORKDIR /ocawe

RUN apt-get update \
  && apt-get install -y --no-install-recommends libsqlite3-dev nodejs npm ruby curl \
  && rm -rf /var/lib/apt/lists/*

# Install CLIs that users may add on canvas (no runtime installs).
RUN npm install -g opencode-ai && test -f /usr/local/bin/opencode

COPY shard.yml shard.lock ./
RUN shards install --production --skip-postinstall --skip-executables

COPY . .
RUN crystal run scripts/patch_nbchannel.cr
RUN shards build ocawe --release --no-debug
RUN cc -Os -s src/tools/rootfs_tar.c -o /ocawe/bin/rootfs_tar
RUN chmod +x /ocawe/entrypoint.sh

EXPOSE 4111

ENTRYPOINT ["bash", "/ocawe/entrypoint.sh"]
