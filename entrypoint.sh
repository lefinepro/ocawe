#!/usr/bin/env bash
set -euo pipefail

workflows_root="${OCAWE_WORKFLOWS_ROOT:-/app}"
mkdir -p "$workflows_root"
echo "[ocawe] entrypoint workflows_root=$workflows_root"

if [[ "${1:-}" == "ocawe" || "${1:-}" == "up" || "${1:-}" == "dev" || "${1:-}" == "build" || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  exec /ocawe/bin/ocawe "$@"
fi

exec /ocawe/bin/ocawe up "$workflows_root" "$@"
