#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
VERSION="${OCAWE_VERSION:-latest}"
INSTALL_DIR="${HOME}/.local/share/ocawe/bin"
BINARY="${INSTALL_DIR}/ocawecore"
CONTAINER_IMAGE="ocawe:latest"
CONTAINER=false
UPDATE=false
CONTAINER_RUNTIME=""

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS] [--] [OCAWE_ARGS...]

Options:
  --container       Run ocawe inside a container instead of a binary
  --runtime NAME    Container runtime to use: docker, nerdctl, or podman
                    (default: auto-detect)
  --version TAG     Use a specific release version (default: ${VERSION})
  --update          Force re-download the binary even if it exists
  --help            Show this help and exit

Environment:
  OCAWE_VERSION     Default release version tag (e.g. v1.0.0)
  OCAWE_PORT        Port mapping for container mode (default: 4111)

Examples:
  ${SCRIPT_NAME} up --port 4111
  ${SCRIPT_NAME} --container up
  ${SCRIPT_NAME} --container --runtime podman up
  ${SCRIPT_NAME} --version v1.2.0 --update up --port 8080
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --container|--docker)
        CONTAINER=true
        shift
        ;;
      --runtime)
        CONTAINER_RUNTIME="$2"
        shift 2
        ;;
      --version)
        VERSION="$2"
        shift 2
        ;;
      --update)
        UPDATE=true
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
      *)
        break
        ;;
    esac
  done
  OCAWE_ARGS=("$@")
}

detect_container_runtime() {
  if [[ -n "${CONTAINER_RUNTIME}" ]]; then
    if ! command -v "${CONTAINER_RUNTIME}" >/dev/null 2>&1; then
      echo "Error: specified container runtime '${CONTAINER_RUNTIME}' not found" >&2
      exit 1
    fi
    return
  fi

  for runtime in docker podman nerdctl; do
    if command -v "${runtime}" >/dev/null 2>&1; then
      CONTAINER_RUNTIME="${runtime}"
      return
    fi
  done

  echo 'Error: no container runtime found (tried: docker, podman, nerdctl)' >&2
  exit 1
}

get_latest_tag() {
  local repo="lefine/ocawe"
  local url="https://api.github.com/repos/${repo}/releases/latest"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${url}" | grep -oP '"tag_name":\s*"\K[^"]+'
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "${url}" | grep -oP '"tag_name":\s*"\K[^"]+'
  else
    echo "Error: curl or wget is required to fetch the latest version" >&2
    exit 1
  fi
}

download_binary() {
  local tag="$1"
  local repo="lefine/ocawe"
  local asset="ocawecore-linux.tar.gz"
  local url="https://github.com/${repo}/releases/download/${tag}/${asset}"
  local tmpdir

  echo "[launch-ocawe] Downloading ocawecore ${tag}..."
  mkdir -p "${INSTALL_DIR}"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' EXIT

  if command -v curl >/dev/null 2>&1; then
    curl -fL "${url}" -o "${tmpdir}/${asset}"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "${tmpdir}/${asset}" "${url}"
  else
    echo "Error: curl or wget is required to download the binary" >&2
    exit 1
  fi

  tar -xzf "${tmpdir}/${asset}" -C "${INSTALL_DIR}"
  chmod +x "${BINARY}"
  echo "[launch-ocawe] Installed to ${BINARY}"
}

run_binary() {
  if [[ "${UPDATE}" == true ]] || [[ ! -x "${BINARY}" ]]; then
    if [[ "${VERSION}" == "latest" ]]; then
      VERSION="$(get_latest_tag)"
    fi
    download_binary "${VERSION}"
  fi
  exec "${BINARY}" "${OCAWE_ARGS[@]}"
}

run_container() {
  detect_container_runtime
  local port="${OCAWE_PORT:-4111}"

  local project_root
  project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

  # OCI implementations share the same CLI contract, so we can use them interchangeably.
  # nerdctl / Lima may also use a special environment variable to read CA certs
  # (other runtimes simply ignore it).
  export OCI_SYSTEM_CERT_DIR="${OCI_SYSTEM_CERT_DIR:-/etc/pki/tls/certs}"

  if ! "${CONTAINER_RUNTIME}" image inspect "${CONTAINER_IMAGE}" >/dev/null 2>&1; then
    echo "[launch-ocawe] Building container image ${CONTAINER_IMAGE} with ${CONTAINER_RUNTIME}..."
    if [[ -f "${project_root}/Dockerfile" ]]; then
      "${CONTAINER_RUNTIME}" build -t "${CONTAINER_IMAGE}" "${project_root}"
    else
      echo "Error: Dockerfile not found in ${project_root}" >&2
      exit 1
    fi
  fi

  local -a container_args=(
    --rm
    -p "${port}:4111"
    -e "OCAWE_PORT=4111"
    -e "OCAWE_WORKDIR=/ocawe/workflows"
    -v "${project_root}:/ocawe"
  )

  # Forward common provider credential directories if they exist on the host
  for cred in ~/.codex ~/.claude ~/.opencode ~/.qwen; do
    if [[ -d "${cred}" ]]; then
      container_args+=(-v "${cred}:${cred}")
    fi
  done

  echo "[launch-ocawe] Starting container with ${CONTAINER_RUNTIME} ${CONTAINER_IMAGE}..."
  exec "${CONTAINER_RUNTIME}" run "${container_args[@]}" "${CONTAINER_IMAGE}" "${OCAWE_ARGS[@]}"
}

main() {
  parse_args "$@"
  if [[ "${CONTAINER}" == true ]]; then
    run_container
  else
    run_binary
  fi
}

main "$@"
