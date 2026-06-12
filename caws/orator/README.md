# Orator - OpenAI API to ActivityPub Gateway

Full replacement for crater-openai, built on the Ocawe framework.

## Overview

Orator converts between OpenAI-like APIs (OpenResponses, ChatCompletion) and ActivityPub federation protocol, enabling AI agents to communicate via ActivityPub.

## Architecture

```
┌─────────────────┐
│ OpenAI Request  │  (POST /v1/responses or /v1/chat/completions)
│ OpenResponses   │
│ ChatCompletion  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ send_to_inbox   │  Convert to ActivityPub Create{Ticket}
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ ActivityPub     │  ForgeFed Ticket via Aptok
│ Inbox/Outbox    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ recevie_from_   │  Convert back to OpenAI format
│ outbox          │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ OpenAI Response │
│ OpenResponses   │
│ ChatCompletion  │
└─────────────────┘
```

## Components

### `converters.cr`
- **OpenResponsesToActivityPub**: Converts OpenResponses requests to ActivityPub Create{Ticket}
- **ChatCompletionToActivityPub**: Converts ChatCompletion requests to ActivityPub Create{Ticket}
- **ActivityPubToOpenResponses**: Converts ActivityPub Create{Note}/Update{Ticket} to OpenResponses
- **ActivityPubToChatCompletion**: Converts ActivityPub to ChatCompletion format

Uses Aptok helpers:
- `Aptok.forgefed_ticket()` - Creates ForgeFed Ticket objects
- `Aptok.create()` - Wraps objects in ActivityPub Create activities

### `translators.cr`
- **SendToInbox**: Translator node that detects format and converts to ActivityPub
- **ReceiveFromOutbox**: Translator node that converts ActivityPub back to original format

Registers custom node kinds with `Ocawe::RegistryApi.node_kind()`.

### Framework Extensions

Added to `src/framework/workflows/declarative/definition/endpoints/control_flow.cr`:
- `follow(actors)` - DSL method for ActivityPub federation subscriptions

Added to `src/framework/registry/api/endpoints/registry_api_build_node.cr`:
- `"follow"` node type handler

Added to `src/framework/workflows/declarative/types.cr`:
- `NodeKind::Federation` enum value

## Usage

```bash
cd caws/orator
ocawe up
```

Then send requests to:
- `POST http://localhost:8080/v1/responses` - OpenResponses format
- `POST http://localhost:8080/v1/chat/completions` - ChatCompletion format

## Cawfile

```crystal
#+name: orator
require "translator"
require "translator/registry"

settings do
  data.adapter = "memory"
  port = 8080
end

struct InputSchema
  include Api::OpenResponses::Request
  include Api::ChatCompletionAPI::Request
end

struct OutputSchema
  include Api::OpenResponses::Response
  include Api::ChatCompletionAPI::Response
end

@[Container(static)]
@[Load(".env")]
@[Validate(InputSchema, OutputSchema)]
workflow "orator" do
  follow ["@actra@lefine.pro"]
  send_to_inbox
  recevie_from_outbox
end
```

## Differences from crater-openai

| Feature | crater-openai | Orator |
|---------|---------------|--------|
| Runtime | Standalone Kemal server | Ocawe workflow |
| Config | RCL config files | Cawfile DSL |
| Provider system | Custom ForgeFedProvider | Translator nodes |
| Discovery | Custom discovery system | Framework federation |
| Startup | `crater-openai --config ...` | `ocawe up` |

## API Compatibility

Fully compatible with crater-openai's:
- `/v1/responses` endpoint (OpenResponses format)
- `/v1/chat/completions` endpoint (ChatCompletion format)
- ActivityPub Create{Ticket} delivery
- ForgeFed metadata handling

## Dependencies

- Ocawe framework (workflows, federation, node registry)
- Aptok library (ActivityPub helpers)
- Crystal standard library
