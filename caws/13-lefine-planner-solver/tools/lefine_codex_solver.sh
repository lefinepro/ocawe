#!/usr/bin/env bash
set -euo pipefail

payload="$(cat)"
tmpdir="${TMPDIR:-/tmp}/lefine-codex-solver"
mkdir -p "$tmpdir"
prompt_file="$(mktemp "$tmpdir/prompt.XXXXXX")"
out_file="$(mktemp "$tmpdir/result.XXXXXX")"
workdir_file="$(mktemp "$tmpdir/workdir.XXXXXX")"

node -e '
const fs = require("fs");
const payload = JSON.parse(process.argv[1] || "{}");
const input = payload.input || payload.ticket || {};
const source = typeof input.source === "object" && input.source ? input.source.content : "";
let sourceJson = {};
try { sourceJson = source ? JSON.parse(source) : {}; } catch {}
const taskRef = input.taskRef || input.task_ref || "";
const task = payload.task || input.content || input.summary || input.name || sourceJson.prompt_intent || "";
const prompt = [
  "Ты Codex solver на сервере dorian для Lefine #plan workflow.",
  "Нужно решить задачу и вернуть короткий пользовательский результат.",
  "Не задавай уточняющие вопросы, используй safest defaults.",
  "Если задача явно просит изменить код, сделай минимальные изменения и кратко опиши результат.",
  "Если задача просит только проверить команду или ответить текстом, не читай репозиторий и не меняй файлы.",
  "Для smoke/test задач верни только требуемую строку без markdown-шума.",
  "Не отправляй HTTP/curl запросы в Fmatch inbox; Ocawe wrapper сам доставит твой финальный текст.",
  "",
  `TaskRef: ${taskRef}`,
  `Task: ${task}`,
  sourceJson.folder_path ? `Folder: ${sourceJson.folder_path}` : "",
  sourceJson.conversation_id ? `Conversation: ${sourceJson.conversation_id}` : ""
].filter(Boolean).join("\n");
fs.writeFileSync(process.argv[2], prompt);
fs.writeFileSync(process.argv[3], sourceJson.folder_path || "");
' "$payload" "$prompt_file" "$workdir_file"

codex_workdir="$(cat "$workdir_file" 2>/dev/null || true)"
if [ -n "$codex_workdir" ] && [ -d "$codex_workdir" ]; then
  cd "$codex_workdir"
fi

if ! command -v codex >/dev/null 2>&1; then
  node -e 'console.log(JSON.stringify({status:"failed",content:"codex CLI is not available in ocawe solver PATH"}))'
  exit 0
fi

set +e
timeout 180s codex --ask-for-approval never exec --sandbox danger-full-access --skip-git-repo-check --output-last-message "$out_file" - < "$prompt_file" >/tmp/lefine-codex-solver.log 2>&1
status=$?
set -e

if [ "$status" -ne 0 ]; then
  message="$(tail -n 80 /tmp/lefine-codex-solver.log | tr '\n' ' ')"
  node -e 'console.log(JSON.stringify({status:"failed",content:process.argv[1] || "codex exec failed"}))' "$message"
  exit 0
fi

result="$(cat "$out_file" 2>/dev/null || true)"
node -e 'console.log(JSON.stringify({status:"completed",content:process.argv[1] || "codex completed without a final message"}))' "$result"
