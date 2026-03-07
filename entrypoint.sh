#!/usr/bin/env bash
set -euo pipefail

PORT="${COGNI_PORT:-4111}"
CONFIG_RCL="${COGNI_CONFIG_RCL:-/cogni/cogni.config.rcl}"
BUILD_ARGS="${COGNI_BUILD_ARGS:---release}"
WORKFLOWS_SRC_PRIMARY="${COGNI_WORKFLOWS_SRC:-/cogni/src/workflow}"
WORKFLOWS_SRC_FALLBACK="${COGNI_WORKFLOWS_FALLBACK_SRC:-/cogni/src/workflows}"

if [[ -d "${WORKFLOWS_SRC_PRIMARY}" ]]; then
  WORKFLOWS_ROOT="${WORKFLOWS_SRC_PRIMARY}"
elif [[ -d "${WORKFLOWS_SRC_FALLBACK}" ]]; then
  WORKFLOWS_ROOT="${WORKFLOWS_SRC_FALLBACK}"
else
  WORKFLOWS_ROOT="${WORKFLOWS_SRC_PRIMARY}"
  mkdir -p "${WORKFLOWS_ROOT}"
fi

echo "[entrypoint] building cogni runtime..."
shards build cognicore ${BUILD_ARGS} -Dcogni_runtime_main

echo "[entrypoint] starting cognicore on port ${PORT} with workflows root ${WORKFLOWS_ROOT}..."
exec ./bin/cognicore \
  --port="${PORT}" \
  --workflows-root="${WORKFLOWS_ROOT}" \
  --fallback-workflows-root="${WORKFLOWS_ROOT}" \
  --config-rcl="${CONFIG_RCL}"
