#!/usr/bin/env bash
set -euo pipefail

PORT="${OCAWE_PORT:-4111}"
CONFIG_RCL="${OCAWE_CONFIG_RCL:-/ocawe/ocawe.config.rcl}"
BUILD_ARGS="${OCAWE_BUILD_ARGS:---release}"
WORKFLOWS_ROOT="${OCAWE_WORKFLOWS_ROOT:-/ocawe/workflows}"
mkdir -p "${WORKFLOWS_ROOT}"

echo "[entrypoint] building ocawe runtime..."
shards build ocawecore ${BUILD_ARGS} -Docawe_runtime_main

echo "[entrypoint] starting ocawecore on port ${PORT} with workflows root ${WORKFLOWS_ROOT}..."
exec ./bin/ocawecore \
  --port="${PORT}" \
  --workflows-root="${WORKFLOWS_ROOT}" \
  --fallback-workflows-root="${WORKFLOWS_ROOT}" \
  --config-rcl="${CONFIG_RCL}"
