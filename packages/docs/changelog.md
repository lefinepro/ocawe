# Changelog

All notable changes to Ocawe will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Cawfile-first framework documentation**
  - Root `Cawfile` support for runtime settings, shared structs, multiple workflows, and `@[Service]` workflows
  - Bundle-local `Cawfile` resolution before legacy `.acd.cr` fallback
  - Service workflow examples for tunnels, daemons, watchers, and schedulers
  - ACP `exec` runtime examples for external agents
  - OpenAI-compatible chat completion retrieval and async task endpoints
  - Dataset API and SQLite-backed task queue documentation

## [26.06.0] - 2026-06-12

### Added

- **Agent Client Protocol (ACP) support** for external agent integration
  - `exec` node with `runtime: { "acp" => {...} }` configuration
  - Full JSON-RPC 2.0 protocol implementation
  - Session management (initialize, session/new, session/prompt, session/cancel)
  - Support for text and resource content blocks
  - Environment variable passing to ACP agents
  - Bidirectional streaming with session updates

- **Workflow execution via model parameter** in /v1/chat/completions
  - Use `model: "workflow/workflow-id"` to execute workflows as chat models
  - Seamless integration with OpenAI-compatible API clients
  - Automatic input/output transformation for chat format

- **/v1/models endpoint** with OpenRouter-compatible format
  - Dynamic model discovery from registered workflows, agents, skills, and tools
  - Opt-in activation via Api::Models module inclusion
  - Returns comprehensive model metadata and capabilities

- **Container packaging** with static and NixOS builders
  - Multi-runtime support (docker, podman, nerdctl)
  - Auto-detection of available container runtimes
  - Static binary builds for portable deployments

- **Gonka provider integration** for LLM inference
  - OpenAI-compatible API with custom base URL support
  - Environment-based configuration (GONKA_API_KEY, GONKA_BASE_URL)
  - Mock mode support for testing

### Changed

- Renamed project from Cogni to Ocawe
- Renamed Cawfile format from .cogni.cr to .acd.cr (Agent Control Definition)
- Refactored API activation to opt-in via type inclusion
  - APIs now activated by including request/response types in Cawfile structs
  - Enforced through @[Validate] annotation
- Improved /v1/models to return workflows/agents/skills/tools instead of static providers
- Replaced @[Packages] annotation with @[Container]
- Removed deprecated import = [...] directive from Cawfile format

### Fixed

- **CI compilation errors** with nil-safe type handling
  - Fixed gonka_provider.cr hash access with proper try chains
  - Fixed acp_executor.cr array mapping using compact_map
  - Fixed JSON::Any type conversions throughout ACP implementation

- **ACP test suite issues**
  - Replaced skip with next for conditional test execution
  - Fixed JSON::Serializable constructor calls
  - Added proper type annotations for empty hashes and arrays

- **Ameba linting issues**
  - Removed trailing whitespace across entire codebase
  - Fixed global variable usage in mock ACP agent
  - Applied Performance/CompactAfterMap suggestion

- **Build system improvements**
  - Build CLI binary before running specs in CI
  - Fixed converter and caws integration
  - Container builder path resolution and runtime detection

### Removed

- Removed custom_provider_macro_spec.cr (stale test for non-existent macro)
- Removed codex/coding references from codebase
- Removed agent-functions require from src/ocawe.cr
- Removed builtin agents that caused test failures
- Removed shards functions and references
- Removed Maddy deployment guides from documentation

### Documentation

- Comprehensive documentation overhaul inspired by Mastra.ai
- Fixed dead links to missing /guides/memory and /guides/mcp pages
- Improved README structure and removed duplicate headings
- Added ACP protocol examples and usage guides
- Added workflow-as-model documentation

### Internal

- Added Metrics/LineCount ameba rule
- Removed rcl.cr exclusion from ameba config
- Clean up models.cr duplicate code
- Improved type safety throughout ACP implementation
- Enhanced error handling in workflow execution

## [0.0.1] - 2026-06-01

### Added

- Initial release of Ocawe framework
- Crystal-native workflow DSL
- Declarative agent definitions
- HTTP API endpoints for workflow execution
- Interactive Svelte playground
- VitePress documentation site
- Basic LLM provider integration
- Workflow state management
- Control flow primitives (parallel, conditional, loops)
- Suspend/resume capabilities
- Schema validation support
- MCP integration foundation
- ActivityPub federation support
- Voice and RAG workflow primitives
