#!/usr/bin/env bash
set -euo pipefail

bundle_dir="${1:-.}"
cawfile="${bundle_dir%/}/Cawfile"

if [[ ! -f "$cawfile" ]]; then
  printf 'error: no Cawfile found at %s\n' "$cawfile" >&2
  exit 2
fi

errors=0
warnings=0

fail() {
  printf 'error: %s\n' "$1" >&2
  errors=$((errors + 1))
}

warn() {
  printf 'warning: %s\n' "$1" >&2
  warnings=$((warnings + 1))
}

contains() {
  if command -v rg >/dev/null 2>&1; then
    rg -q -- "$1" "$cawfile"
  else
    grep -Eq -- "$1" "$cawfile"
  fi
}

contains '^[[:space:]]*workflow[[:space:]]+"[^"]+"[[:space:]]+do' || fail "declare at least one workflow"
contains '@\[Validate\(' || fail "validate workflow input and output with @[Validate(...)]"
contains '^[[:space:]]*test[[:space:]]+"[^"]+"[[:space:]]+do' || fail "add at least one Cawfile test block"

if contains '(:latest|"latest")'; then
  fail "replace floating latest references with immutable versions"
fi

if contains 'runtime:[[:space:]]*\{[[:space:]]*"git\+(https|ssh)"'; then
  fail "remote workflow execution is mutable unless an immutable revision is supported and declared"
fi

if contains '(curl|wget)[^#\n]*(\|[[:space:]]*(sh|bash)|-O[[:space:]]+-)'; then
  fail "do not download and execute mutable remote content inside the pipeline"
fi

if contains '(^|[^A-Za-z_])(rand|Random\.|Time\.utc|Time\.local|/home/|~/)'; then
  warn "review randomness, wall-clock time, or host-specific paths and inject them as inputs"
fi

if contains '^[[:space:]]*(agent[[:space:]]|agent\()' && ! contains '@\[Model\(|model:[[:space:]]*"'; then
  fail "set an explicit model for every model-backed workflow or agent"
fi

if contains '^[[:space:]]*container[[:space:]]+do' && ! contains '^[[:space:]]*files[[:space:]]*='; then
  warn "container copies implicit bundle contents; use an explicit files allowlist for a stable artifact"
fi

if (( errors > 0 )); then
  printf 'check failed: %d error(s), %d warning(s)\n' "$errors" "$warnings" >&2
  exit 1
fi

printf 'check passed: %s (%d warning(s))\n' "$cawfile" "$warnings"
