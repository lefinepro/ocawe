#!/usr/bin/env bash
set -euo pipefail

repo="${OCAWE_REPO:-lefinepro/ocawe}"
version="${OCAWE_VERSION:-latest}"
install_dir="${OCAWE_INSTALL_DIR:-$HOME/.local}"
base_url="${OCAWE_BASE_URL:-}"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

case "$(uname -s)" in
  Linux) os="linux" ;;
  *)
    echo "unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

case "$(uname -m)" in
  x86_64 | amd64) arch="x86_64" ;;
  *)
    echo "unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

asset="ocawe-${os}-${arch}.tar.gz"

if [ -n "$base_url" ]; then
  url="${base_url%/}/${asset}"
elif [ "$version" = "latest" ]; then
  url="https://github.com/${repo}/releases/latest/download/${asset}"
else
  url="https://github.com/${repo}/releases/download/${version}/${asset}"
fi

mkdir -p "$install_dir"
echo "Installing ocawe ${version} to ${install_dir}" >&2

if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$url" -o "$tmp_dir/ocawe.tar.gz"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$tmp_dir/ocawe.tar.gz" "$url"
else
  echo "curl or wget is required" >&2
  exit 1
fi

tar -xzf "$tmp_dir/ocawe.tar.gz" -C "$install_dir"

if [ ! -x "$install_dir/bin/ocawe" ]; then
  echo "install failed: $install_dir/bin/ocawe was not created" >&2
  exit 1
fi

echo "Installed: $install_dir/bin/ocawe" >&2
if ! command -v ocawe >/dev/null 2>&1; then
  echo "Add $install_dir/bin to PATH to run ocawe from any directory." >&2
fi
