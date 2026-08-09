#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
mirror_url="${OCAWE_SOURCE_MIRROR_URL:-ssh://git@source.lefine.pro:2222/lefinepro/ocawe.git}"

git -C "${repo_root}" rev-parse --is-inside-work-tree >/dev/null
git -C "${repo_root}" push --mirror "${mirror_url}"
