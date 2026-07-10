#!/bin/sh
set -eu

PORT="${OCAWE_PORT:-4111}"
BUILD_ARGS="${OCAWE_BUILD_ARGS:---release}"
WORKDIR="${OCAWE_WORKDIR:-/ocawe/workflows}"
mkdir -p "${WORKDIR}"

echo "[entrypoint] building ocawe runtime..."
shards build ocawecore ${BUILD_ARGS} -Docawe_runtime_main

CONFIG_RCL_ARG=""
if [ -n "${OCAWE_CONFIG_RCL:-}" ]; then
  CONFIG_RCL_ARG=" --config-rcl=${OCAWE_CONFIG_RCL}"
fi

echo "[entrypoint] starting ocawecore on port ${PORT} in ${WORKDIR}..."
cd "${WORKDIR}"
exec /ocawe/bin/ocawecore \
  --port="${PORT}"${CONFIG_RCL_ARG}
