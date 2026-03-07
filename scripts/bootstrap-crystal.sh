#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TOOLS_DIR="${PROJECT_ROOT}/.tools"

if command -v crystal >/dev/null 2>&1 && [[ "${COGNI_CRYSTAL_FORCE_BOOTSTRAP:-0}" != "1" ]]; then
  exit 0
fi

VERSION="${COGNI_CRYSTAL_VERSION:-1.13.3}"
OS="$(uname -s)"
ARCH="$(uname -m)"

case "${OS}" in
  Linux) OS_TAG="linux" ;;
  Darwin) OS_TAG="darwin" ;;
  *)
    echo "[cogni] unsupported OS for Crystal bootstrap: ${OS}" >&2
    exit 1
    ;;
esac

case "${ARCH}" in
  x86_64|amd64) ARCH_TAG="x86_64" ;;
  aarch64|arm64)
    if [[ "${OS_TAG}" == "darwin" ]]; then
      ARCH_TAG="universal"
    else
      ARCH_TAG="aarch64"
    fi
    ;;
  *)
    echo "[cogni] unsupported CPU architecture for Crystal bootstrap: ${ARCH}" >&2
    exit 1
    ;;
esac

if [[ "${OS_TAG}" == "darwin" ]]; then
  ARCHIVE_NAME="crystal-${VERSION}-1-darwin-universal.tar.gz"
  TARGET="darwin-universal"
else
  ARCHIVE_NAME="crystal-${VERSION}-1-${OS_TAG}-${ARCH_TAG}.tar.gz"
  TARGET="${OS_TAG}-${ARCH_TAG}"
fi

BASE_URL="${COGNI_CRYSTAL_BASE_URL:-https://github.com/crystal-lang/crystal/releases/download}"
ARCHIVE_URL="${BASE_URL}/${VERSION}/${ARCHIVE_NAME}"

INSTALL_DIR="${TOOLS_DIR}/crystal/${VERSION}/${TARGET}"
CACHE_DIR="${TOOLS_DIR}/cache"
ARCHIVE_PATH="${CACHE_DIR}/${ARCHIVE_NAME}"

mkdir -p "${CACHE_DIR}" "$(dirname "${INSTALL_DIR}")"

if [[ ! -x "${INSTALL_DIR}/bin/crystal" ]]; then
  echo "[cogni] crystal not found, bootstrapping ${VERSION} for ${TARGET}"

  if [[ ! -f "${ARCHIVE_PATH}" ]]; then
    echo "[cogni] downloading ${ARCHIVE_URL}"
    if command -v curl >/dev/null 2>&1; then
      curl -fL "${ARCHIVE_URL}" -o "${ARCHIVE_PATH}"
    elif command -v wget >/dev/null 2>&1; then
      wget -O "${ARCHIVE_PATH}" "${ARCHIVE_URL}"
    else
      echo "[cogni] neither curl nor wget is available to download Crystal" >&2
      exit 1
    fi
  fi

  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${TMP_DIR}"' EXIT

  tar -xzf "${ARCHIVE_PATH}" -C "${TMP_DIR}"
  CRYSTAL_BIN="$(find "${TMP_DIR}" -type f -path '*/bin/crystal' | head -n 1)"

  if [[ -z "${CRYSTAL_BIN}" ]]; then
    echo "[cogni] failed to locate crystal binary inside archive ${ARCHIVE_NAME}" >&2
    exit 1
  fi

  ROOT_DIR="$(cd "$(dirname "${CRYSTAL_BIN}")/.." && pwd)"
  rm -rf "${INSTALL_DIR}"
  cp -R "${ROOT_DIR}" "${INSTALL_DIR}"
fi

export PATH="${INSTALL_DIR}/bin:${PATH}"

if [[ "${COGNI_CRYSTAL_VERBOSE:-0}" == "1" ]]; then
  crystal --version
fi
