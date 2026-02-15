# config-example (Crystal config)

Framework configuration is defined directly in Crystal (`AppConfig`), not TOML runtime files.

Use this file as a template:

- `shards/examples/config-example/app_config.cr`

Typical approach:

1. Copy the constants and `settings` shape into `src/framework/cognicore/config/app_config.cr`.
2. Point `WORKFLOW_PREFERRED_ROOT` / `WORKFLOW_FALLBACK_ROOT` to your bundle roots.
3. Put any `snake_case` Crystal handlers in `settings.functions`; runtime auto-registers them on startup.
