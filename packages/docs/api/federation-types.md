# API Federation Types

Ocawe provides built-in types for federation workflows with ActivityPub/ForgeFed validation.

## Usage

Include `Api::Federation::Inbox` or `Api::Federation::Outbox` in your Cawfile structs to automatically enable federation API and get type-safe validation:

```crystal
# Cawfile
settings do
  port = 4111
  datasets.adapter = "sqlite"
  
  federation do
    local_actor = "https://your.domain/actors/codex"
    local_private_key_path = "./.ocawe/federation-private.pem"
  end
end

# Federation types - automatically enables federation API
struct InputCodex
  include Api::Federation::Inbox
end

struct OutputCodex
  include Api::Federation::Outbox
end

@[Validate(InputCodex, OutputCodex)]
@[Load(["AGENTS.md"])]
container do
  packages = ["git", "curl"]
end

workflow "codex" do
  follow ["@searcher@lefine.pro", "@coder@lefine.pro"]
  agent_codex
end
```

## Type Validation

### `Api::Federation::Inbox`

Validates incoming ActivityPub activities with support for:
- Core activities: `Create`, `Update`, `Delete`, `Follow`, `Accept`, `Reject`, `Add`, `Remove`, `Like`, `Announce`, `Undo`, `Block`, `Flag`
- ForgeFed activities: `Offer`, `Resolve`, `Apply`, `Grant`, `Revoke`

Required fields:
- `@context` — must include ActivityPub namespace (`https://www.w3.org/ns/activitystreams`)
- `type` — activity type (string)
- `id` — activity ID (string URI)
- `actor` — actor ID (string URI or object)

## Automatic Federation Enablement

When `Api::Federation::Inbox` or `Api::Federation::Outbox` is included in a Cawfile struct:
1. `CawfileLoader` detects usage and sets `enable_federation = true`
2. `ConfigParser` automatically adds `"federation"` to `api.enabled`
3. `App.start` mounts Aptok federation endpoints (`/actors/*`, `/inbox`, WebFinger, NodeInfo)
4. `bootstrap_federation_subscriptions` auto-subscribes to `follow` targets

No manual configuration needed — just include the types.
