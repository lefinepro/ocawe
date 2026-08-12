# Examples

Examples live under `caws/` as Cawfile workflow bundles.

## Run An Example

```bash
ocawe up caws/01-simple
ocawe up -d caws/02-multi-agent
ocawe pull git+https://github.com/lefinepro/ocawe/caws/10-acp-agent
```

## Bundles

- `01-simple`: minimal single agent setup.
- `02-multi-agent`: sequential agent pipeline.
- `03-control-flow`: `unless`, `if/else`, `parallel`, `while`, and `until`.
- `04-rag-assistant`: RAG workflow with vector store.
- `05-voice-pipeline`: voice transcription and synthesis.
- `06-full-suite`: combined features, container packaging, and multiple service workflows.
- `09-custom-agent`: custom agents backed by external binaries.
- `10-acp-agent`: ACP-compatible external agent execution.
- `14-commands-api`: local function plugins, bare function invocation, and a guarded agent.
- `15-reproducible-pipeline`: typed, tested local-function pipeline with no external dependencies.
- `11-git-https-pull`: pulling remote Cawfile bundles with `git+https`.
- `12-api-nodes`: HTTP `get`, `post`, and `put` steps with `step["name"]` result access.

## API Step Demo

`caws/12-api-nodes` is self-contained. Start the mock API first:

```bash
nix develop --command crystal run caws/12-api-nodes/mock_api.cr
```

Then run Ocawe with the API workflow:

```bash
nix develop --command crystal run src/cli/main.cr -- up caws/12-api-nodes --port 4111
```

Trigger the workflow:

```bash
curl -s -X POST http://127.0.0.1:4111/v1/triggers/workflows/api \
  -H 'Content-Type: application/json' \
  -d '{}'
```

The workflow calls `GET /weather`, branches on `step["weather"].current.temperature_2m`, and sends the current weather payload to `POST /farm/start`.

## Notes

- Use `agent`, `skill`, `rag`, `voice`, `exec`, or internal function-name nodes for workflow work.
- Use API steps when the workflow needs deterministic HTTP calls:

```crystal
workflow "api" do
  get "http://127.0.0.1:5055/weather", id: "weather"

  if step["weather"].current.temperature_2m > 0
    post "http://127.0.0.1:5055/farm/start",
      id: "start-farm",
      body: step["weather"].current
  end
end
```

- `id:` is the step name used by later expressions.
- API step results include `step`, `status`, `headers`, `body`, and `raw_body`.
- JSON object response fields are also exposed directly, so `step["weather"].current` works without writing `step["weather"].body.current`.
