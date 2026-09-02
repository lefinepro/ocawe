#!/usr/bin/env bash
set -euo pipefail

payload="$(cat)"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
runner="$script_dir/run-codex-plan.sh"

if [ ! -x "$runner" ]; then
  jq -n --arg content "RepositoryArchive Codex runner is not available: $runner" \
    '{status:"failed",content:$content}'
  exit 0
fi

runner_output="$(printf '%s' "$payload" | "$runner")"
runner_status="$(printf '%s' "$runner_output" | jq -r '.status // "failed"')"
result_text="$(printf '%s' "$runner_output" | jq -r '.result_text // .content // .error // empty')"

if [ -z "${result_text//[[:space:]]/}" ]; then
  result_text="$runner_output"
fi

jq -n \
  --arg status "$runner_status" \
  --arg content "$result_text" '
    {
      status: $status,
      content: $content,
      result_text: $content
    }
  '
