#!/run/current-system/sw/bin/bash
set -euo pipefail

session_id="solver-$(date +%s%N)"

reply() {
  /run/current-system/sw/bin/jq -cn --argjson id "$1" --argjson result "$2" \
    '{jsonrpc:"2.0",id:$id,result:$result}'
}

error_reply() {
  /run/current-system/sw/bin/jq -cn --argjson id "$1" --arg message "$2" \
    '{jsonrpc:"2.0",id:$id,error:{code:-32603,message:$message}}'
}

while IFS= read -r line; do
  method=$(printf '%s' "$line" | /run/current-system/sw/bin/jq -r '.method // empty')
  id=$(printf '%s' "$line" | /run/current-system/sw/bin/jq -c '.id // null')

  case "$method" in
    initialize)
      reply "$id" '{"protocolVersion":1,"agentCapabilities":{"loadSession":true,"promptCapabilities":{"image":false,"audio":false,"embeddedContext":true}},"agentInfo":{"name":"codex","title":"Codex","version":"cli"}}'
      ;;
    session/new)
      reply "$id" "$(/run/current-system/sw/bin/jq -cn --arg sessionId "$session_id" '{sessionId:$sessionId}')"
      ;;
    session/prompt)
      prompt=$(printf '%s' "$line" | /run/current-system/sw/bin/jq -r '.params.prompt[0].text // ""')
      tmp=$(mktemp)
      err=$(mktemp)
      if output=$(printf '%s' "$prompt" | CODEX_HOME=/root/.codex /root/.nix-profile/bin/codex exec --ephemeral --skip-git-repo-check -s read-only - 2>"$err"); then
        :
      else
        output=$(cat "$err")
      fi
      rm -f "$tmp" "$err"
      notification=$(/run/current-system/sw/bin/jq -cn --arg sid "$session_id" --arg text "$output" \
        '{jsonrpc:"2.0",method:"session/update",params:{sessionId:$sid,update:{sessionUpdate:"agent_message_chunk",content:{type:"text",text:$text}}}}')
      printf '%s\n' "$notification"
      result=$(/run/current-system/sw/bin/jq -cn '{"stopReason":"end_turn"}')
      reply "$id" "$result"
      ;;
    *)
      if [ "$id" != null ]; then
        error_reply "$id" "unsupported ACP method: $method"
      fi
      ;;
  esac
done
