#!/usr/bin/env bash
set -euo pipefail

input_json="$(mktemp)"
repo_archive="$(mktemp)"
repo_root="$(mktemp -d)"
workspace="$(mktemp -d)"
codex_stdout="$(mktemp)"
codex_stderr="$(mktemp)"
trap 'rm -f "$input_json" "$repo_archive" "$codex_stdout" "$codex_stderr"; rm -rf "$repo_root" "$workspace"' EXIT

cat >"$input_json"

fail_json() {
  jq -n --arg message "$1" '{
    status: "failed",
    result_text: $message,
    error: $message
  }'
  exit 0
}

command -v jq >/dev/null 2>&1 || fail_json "planner requires jq"
command -v base64 >/dev/null 2>&1 || fail_json "planner requires base64"
command -v sha256sum >/dev/null 2>&1 || fail_json "planner requires sha256sum"
command -v tar >/dev/null 2>&1 || fail_json "planner requires tar"

container_tool="${OCAWE_CONTAINER_TOOL:-nerdctl}"
container_image="${OCAWE_CODEX_CONTAINER_IMAGE:-busybox:1.36}"
default_codex_bin="$(command -v codex || true)"
codex_bin="${OCAWE_CODEX_BIN:-$default_codex_bin}"
codex_home="${OCAWE_CODEX_HOME:-${HOME:-/root}/.codex}"
timeout_seconds="${OCAWE_CODEX_TIMEOUT_SECONDS:-900}"
codex_sandbox="${OCAWE_CODEX_SANDBOX:-danger-full-access}"

read -r -a container_tool_cmd <<<"$container_tool"
command -v "${container_tool_cmd[0]}" >/dev/null 2>&1 || fail_json "container runtime not found: $container_tool"
if [ -z "$codex_bin" ] || [ ! -x "$codex_bin" ]; then
  fail_json "codex binary not found; set OCAWE_CODEX_BIN"
fi

archive_query='
  [
    .ticket?.attachment?,
    .input?.attachment?,
    .federation_input?.ticket?.attachment?
  ]
  | map(if type == "array" then .[] elif type == "object" then . else empty end)
  | map(select(.type == "RepositoryArchive"))
  | .[0] // null
'

archive_json="$(jq -c "$archive_query" "$input_json")"
if [ "$archive_json" = "null" ] || [ -z "$archive_json" ]; then
  fail_json "planner requires Ticket attachment with type RepositoryArchive"
fi

archive_content="$(printf '%s' "$archive_json" | jq -r '.content // .content_base64 // empty')"
archive_sha="$(printf '%s' "$archive_json" | jq -r '.sha256 // empty')"
archive_slug="$(printf '%s' "$archive_json" | jq -r '.slug // .name // "repository"')"
if [ -z "$archive_content" ]; then
  fail_json "RepositoryArchive content is empty"
fi

printf '%s' "$archive_content" | base64 -d >"$repo_archive" || fail_json "RepositoryArchive content is not valid base64"
if [ -n "$archive_sha" ]; then
  actual_sha="$(sha256sum "$repo_archive" | awk '{print $1}')"
  if [ "$actual_sha" != "$archive_sha" ]; then
    fail_json "RepositoryArchive sha256 mismatch: expected $archive_sha got $actual_sha"
  fi
fi

if tar -tzf "$repo_archive" | awk 'BEGIN {bad=0} /^\// || /(^|\/)\.\.($|\/)/ {bad=1} END {exit bad}'; then
  tar -xzf "$repo_archive" -C "$repo_root"
else
  fail_json "RepositoryArchive contains unsafe paths"
fi

first_dir="$(find "$repo_root" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [ -n "$first_dir" ] && [ "$(find "$repo_root" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = "1" ]; then
  cp -a "$first_dir"/. "$workspace"/
else
  cp -a "$repo_root"/. "$workspace"/
fi

task="$(jq -r '.task // .federation_input.task // .ticket.name // .ticket.summary // .ticket.content // .input.name // .input.summary // .input.content // empty' "$input_json")"
content="$(jq -r '.content // .federation_input.content // .ticket.content // .input.content // empty' "$input_json")"
ticket_id="$(jq -r '.ticket_id // .federation_input.ticket_id // .ticket.id // .input.id // empty' "$input_json")"

prompt_file="$workspace/.ocawe-codex-prompt.txt"
result_file="$workspace/.ocawe-codex-result.txt"
container_home="$workspace/.home"
container_codex_home="$workspace/.codex"
mkdir -p "$container_home" "$container_codex_home"
if [ -d "$codex_home" ]; then
  cp -a "$codex_home"/. "$container_codex_home"/
fi
cat >"$prompt_file" <<EOF_PROMPT
Ты выполняешь #plan задачу внутри чистого контейнера.

Задача:
$task

Контент тикета:
$content

Репозиторий "$archive_slug" уже распакован прямо в текущую рабочую директорию /workspace.
Файлы проекта лежат в /workspace; отдельного подкаталога с именем репозитория может не быть.
Изучи только файлы в /workspace и верни итоговый ответ. Не меняй файлы, если задача просит только анализ.
EOF_PROMPT

container_args=(
  run
  --rm
  -i
  --network host
  --user "$(id -u):$(id -g)"
  --name "ocawe-codex-plan-$(date +%s)-$$"
  -v /nix/store:/nix/store:ro
  -v /etc/profiles:/etc/profiles:ro
  -v "$workspace:/workspace:rw"
  -e HOME=/workspace/.home
  -e CODEX_HOME=/workspace/.codex
  -w /workspace
)

if [ -d /etc/ssl ]; then
  container_args+=(-v /etc/ssl:/etc/ssl:ro)
fi
if [ -d /etc/pki ]; then
  container_args+=(-v /etc/pki:/etc/pki:ro)
fi
if [ -d /etc/static ]; then
  container_args+=(-v /etc/static:/etc/static:ro)
fi
if [ -f /etc/ssl/certs/ca-certificates.crt ]; then
  container_args+=(-e SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt -e NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt)
elif [ -f /etc/ssl/certs/ca-bundle.crt ]; then
  container_args+=(-e SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt -e NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt)
elif [ -f /etc/pki/tls/certs/ca-bundle.crt ]; then
  container_args+=(-e SSL_CERT_FILE=/etc/pki/tls/certs/ca-bundle.crt -e NIX_SSL_CERT_FILE=/etc/pki/tls/certs/ca-bundle.crt)
fi

container_args+=(
  "$container_image"
  "$codex_bin"
  exec
  --skip-git-repo-check
  --sandbox "$codex_sandbox"
  --cd /workspace
  --output-last-message /workspace/.ocawe-codex-result.txt
  -
)

if command -v timeout >/dev/null 2>&1; then
  timeout "$timeout_seconds" "${container_tool_cmd[@]}" "${container_args[@]}" <"$prompt_file" >"$codex_stdout" 2>"$codex_stderr" || {
    code=$?
    fail_json "codex container failed with exit code $code: $(tail -n 40 "$codex_stderr")"
  }
else
  "${container_tool_cmd[@]}" "${container_args[@]}" <"$prompt_file" >"$codex_stdout" 2>"$codex_stderr" || {
    code=$?
    fail_json "codex container failed with exit code $code: $(tail -n 40 "$codex_stderr")"
  }
fi

if [ -s "$result_file" ]; then
  result_text="$(cat "$result_file")"
else
  result_text="$(cat "$codex_stdout")"
fi

if [ -z "${result_text//[[:space:]]/}" ]; then
  fail_json "codex container completed without result text"
fi

jq -n \
  --arg status "completed" \
  --arg result_text "$result_text" \
  --arg ticket_id "$ticket_id" \
  --arg repo_slug "$archive_slug" \
  '{
    status: $status,
    result_text: $result_text,
    ticket_id: $ticket_id,
    repository: $repo_slug
  }'
