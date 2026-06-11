FROM nixos/nix:2.24.9

RUN nix-channel --update && nix-env -iA nixpkgs.glibc

COPY ocawecore /app/ocawecore
RUN chmod +x /app/ocawecore

EXPOSE 4111

ENTRYPOINT ["/app/ocawecore"]
CMD ["--port", "4111"]
