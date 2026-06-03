# Federation

## Supported federation protocols and standards

- [ActivityPub](https://www.w3.org/TR/activitypub/) (Server-to-Server)
- [HTTP Signatures](https://datatracker.ietf.org/doc/html/draft-cavage-http-signatures)

## Supported FEPs

- [FEP-67ff: FEDERATION.md](https://codeberg.org/fediverse/fep/src/branch/main/fep/67ff/fep-67ff.md)
- [FEP-EF61: ForgeFed Object and Actor support](https://codeberg.org/fediverse/fep/src/branch/main/fep/ef61/fep-ef61.md)

## ActivityPub / ForgeFed interoperability

- Exposes Aptok S2S endpoints:
  - `POST /actors/{identifier}/inbox` (inbound activities)
  - `GET /actors/{identifier}/outbox` (local outbox)
  - `POST /actors/{identifier}/outbox` (outbound activities)
- Supports JSON-LD objects validated against ActivityStreams and ForgeFed contexts.
- Supports ForgeFed actor and object validation for known types used by the system.

## Additional documentation

- [README.md](./README.md)
