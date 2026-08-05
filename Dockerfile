FROM crystallang/crystal:1.13.3

WORKDIR /ocawe

RUN apt-get update \
  && apt-get install -y --no-install-recommends libsqlite3-dev nodejs npm ruby curl \
  && rm -rf /var/lib/apt/lists/*

# Install CLIs that users may add on canvas (no runtime installs).
RUN npm install -g opencode-ai && test -f /usr/local/bin/opencode

COPY shard.yml shard.lock ./
RUN shards update --production --skip-postinstall --skip-executables \
  && if [ -f lib/nbchannel/src/nbchannel.cr ]; then \
      perl -pi -e 's/Crystal::Scheduler\\.reschedule/Fiber.yield/' lib/nbchannel/src/nbchannel.cr \
    ; fi

COPY . .
RUN shards build ocawe --release --no-debug \
  && crystal build src/ocawe.cr -Docawe_runtime_main --release --no-debug -o /ocawe/bin/ocawecore
RUN cc -Os -s src/tools/rootfs_tar.c -o /ocawe/bin/rootfs_tar
RUN chmod +x /ocawe/entrypoint.sh

EXPOSE 4111

ENTRYPOINT ["bash", "/ocawe/entrypoint.sh"]
