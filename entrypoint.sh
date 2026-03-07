#!/usr/bin/env bash
set -euo pipefail

PORT="${COGNI_PORT:-4111}"
CONFIG_RCL="${COGNI_CONFIG_RCL:-/cogni/cogni.config.rcl}"
BUILD_ARGS="${COGNI_BUILD_ARGS:---release}"

echo "[entrypoint] building cogni runtime..."
./bin/cogni build ${BUILD_ARGS}

echo "[entrypoint] starting cogni on port ${PORT}..."
exec ./bin/cogni up --port "${PORT}" --config-rcl "${CONFIG_RCL}"
