# Cawfile Example

Save as `Cawfile` or `.caw` in a workflow bundle directory. Format is **RCL** (not YAML).

```rcl
id = "solver-example"
version = "1.0.0"
description = "Example workflow bundle defined in Cawfile"

packages do
  nix = ["git", "docker", "nodejs"]
end

docker do
  from = "ubuntu:22.04"
  install_nix = true
  expose = [4111]
  cmd = ["./bin/ocawecore"]
  env do
    PORT = "4111"
  end
  copy_paths = ["."]
  build_commands = ["shards build ocawecore --release"]
end

keys = [
  { name = "OPENAI_API_KEY", required = true, description = "OpenAI API key for agent generation", provider = "openai" },
  { name = "ANTHROPIC_API_KEY", required = false, description = "Optional Anthropic key", provider = "anthropic" }
]

agents = [
  { id = "code-reviewer", prompt = "You are a strict code reviewer. Report issues concisely.", model = "qwen3-coder", description = "Code review agent" },
  { id = "deploy-summarizer", prompt = "Summarize deployment plans.", model = "qwen3-coder" }
]

skills = [
  { id = "healthcheck", name = "Health Check", description = "Verify service health", file = "skills/healthcheck.md" }
]

workflow do
  steps = [
    { type = "agent", id = "code-reviewer" },
    { type = "suspend", id = "approval", reason = "Awaiting deploy approval" },
    { type = "exec", id = "deploy-script", runtime = { command = "./scripts/deploy.sh" } },
    { type = "agent", id = "deploy-summarizer" }
  ]
end
```

## Key API

### Keys
- `POST /v1/keys` — add a key (name, value, provider, description)
- `GET /v1/keys` — list keys (values hidden)
- `GET /v1/keys/:name` — get key metadata
- `PUT /v1/keys/:name` — update key value/metadata
- `DELETE /v1/keys/:name` — remove key

### Dockerfile generation
From a Cawfile directory:
```bash
crystal run -e 'require "./src/framework/discovery/cawfile_loader"; puts ACD::Discovery::CawfileLoader.generate_dockerfile(ACD::Discovery::CawfileLoader.load(".", "my-app").not_nil!)'
```
