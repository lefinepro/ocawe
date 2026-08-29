FROM nixos/nix:2.28.3

WORKDIR /ocawe

COPY . .
RUN nix build .#ocawe --print-build-logs \
  && mkdir -p /ocawe/bin \
  && cp -L result/bin/ocawe /ocawe/bin/ocawe \
  && cp -L result/bin/ocawecore /ocawe/bin/ocawecore \
  && cp -L result/bin/rootfs_tar /ocawe/bin/rootfs_tar
RUN chmod +x /ocawe/entrypoint.sh

EXPOSE 4111

ENTRYPOINT ["bash", "/ocawe/entrypoint.sh"]
