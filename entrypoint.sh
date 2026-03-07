#!/usr/bin/env bash
set -euo pipefail

PORT="${COGNI_PORT:-4111}"
CONFIG_RCL="${COGNI_CONFIG_RCL:-/cogni/cogni.config.rcl}"
BUILD_ARGS="${COGNI_BUILD_ARGS:---release}"
WORKFLOWS_ROOT="${COGNI_WORKFLOWS_ROOT:-/cogni/workflows}"
mkdir -p "${WORKFLOWS_ROOT}"

echo "[entrypoint] building cogni runtime..."
shards build cognicore ${BUILD_ARGS} -Dcogni_runtime_main

echo "[entrypoint] starting cognicore on port ${PORT} with workflows root ${WORKFLOWS_ROOT}..."
exec ./bin/cognicore \
  --port="${PORT}" \
  --workflows-root="${WORKFLOWS_ROOT}" \
  --fallback-workflows-root="${WORKFLOWS_ROOT}" \
  --config-rcl="${CONFIG_RCL}"
