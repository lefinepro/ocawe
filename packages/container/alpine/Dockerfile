FROM alpine:3.19

RUN apk add --no-cache ca-certificates openssl

COPY ocawecore /app/ocawecore
RUN chmod +x /app/ocawecore

EXPOSE 4111

ENTRYPOINT ["/app/ocawecore"]
CMD ["--port", "4111"]
