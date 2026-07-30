#!/usr/bin/env bash
set -euo pipefail

payload="$(cat)"
tmpdir="${TMPDIR:-/tmp}/lefine-codex-solver"
mkdir -p "$tmpdir"
prompt_file="$(mktemp "$tmpdir/prompt.XXXXXX")"
out_file="$(mktemp "$tmpdir/result.XXXXXX")"
workdir_file="$(mktemp "$tmpdir/workdir.XXXXXX")"

jq -r '
  def source_json:
    (((.input // .ticket // {}).source.content // "{}") | fromjson? // {});

  . as $payload
  | (($payload.input // $payload.ticket // {}) as $input
    | source_json as $source
    | [
        "Ты Codex solver на сервере dorian для Lefine #plan workflow.",
        "Нужно решить задачу и вернуть короткий пользовательский результат.",
        "Не задавай уточняющие вопросы, используй safest defaults.",
        "Если задача явно просит изменить код, сделай минимальные изменения и кратко опиши результат.",
        "Если задача просит только проверить команду или ответить текстом, не читай репозиторий и не меняй файлы.",
        "Для smoke/test задач верни только требуемую строку без markdown-шума.",
        "Не отправляй HTTP/curl запросы в Fmatch inbox; Ocawe wrapper сам доставит твой финальный текст.",
        "",
        "TaskRef: \($input.taskRef // $input.task_ref // "")",
        "Task: \($input.content // $source.prompt_intent // $input.summary // $payload.task // $input.name // "")",
        (if $source.folder_path then "Folder: \($source.folder_path)" else empty end),
        (if $source.conversation_id then "Conversation: \($source.conversation_id)" else empty end)
      ]
      | map(select(. != ""))
      | join("\n"))
' <<<"$payload" > "$prompt_file"

jq -r '
  (((.input // .ticket // {}).source.content // "{}") | fromjson? // {}).folder_path // ""
' <<<"$payload" > "$workdir_file"

codex_workdir="$(cat "$workdir_file" 2>/dev/null || true)"
if [ -n "$codex_workdir" ] && [ -d "$codex_workdir" ]; then
  cd "$codex_workdir"
fi

if ! command -v codex >/dev/null 2>&1; then
  jq -n --arg content "codex CLI is not available in ocawe solver PATH" '{status:"failed",content:$content}'
  exit 0
fi

set +e
timeout 180s codex --ask-for-approval never exec --sandbox danger-full-access --skip-git-repo-check --output-last-message "$out_file" - < "$prompt_file" >/tmp/lefine-codex-solver.log 2>&1
status=$?
set -e

if [ "$status" -ne 0 ]; then
  message="$(tail -n 80 /tmp/lefine-codex-solver.log | tr '\n' ' ')"
  jq -n --arg content "${message:-codex exec failed}" '{status:"failed",content:$content}'
  exit 0
fi

result="$(cat "$out_file" 2>/dev/null || true)"
jq -n --arg content "${result:-codex completed without a final message}" '{status:"completed",content:$content}'
